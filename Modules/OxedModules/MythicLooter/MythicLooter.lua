-- ============================================================================
-- MythicLooter (built-in OxedHub module)
-- Complete Mythic+ & Raid loot overview, Best-in-Slot planner, drop reminders,
-- vault tracker, and keystone tooltips.
--
-- Features:
--   * Full Season 2 / M+ Dungeons & Raids loot table browser
--   * Best-in-Slot (BIS) item tagging & keystoneloot.io import
--   * Spec & Role check drop reminders before key start
--   * Automated party drop notification & whisper requests
--   * Keystone tooltips with dungeon loot overview
--   * Catalyst & Upgrade tracks browser
--   * Slash commands: /mythicloot, /mythiclooter, /ml, /ksl, /keyloot
-- ============================================================================

local addonName, OxedHub = ...

-- ── Namespace Initialization ────────────────────────────────────────────────
OxedHub.MythicLooter = OxedHub.MythicLooter or {}
_G.MythicLooter = OxedHub.MythicLooter
_G.KeystoneLoot = OxedHub.MythicLooter

local MythicLooter = OxedHub.MythicLooter
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

-- ── Options Window ──────────────────────────────────────────────────────────
local optionsWindow

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("MythicLooter", 460, 480)

        optionsWindow:AddNote("Full Mythic+ & Raid loot overview, Best-in-Slot planner, drop reminders, vault tracker, and keystone tooltips.")

        -- Quick Action Buttons
        local btnOpen = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnOpen:SetSize(200, 24)
        btnOpen:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 20, optionsWindow.cursorY - 2)
        btnOpen:SetText("Open Loot Browser (/ml)")
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            OxedHub.UI:ApplyRedButtonStyle(btnOpen)
        end
        btnOpen:SetScript("OnClick", function()
            if KeystoneLootFrame then
                KeystoneLootFrame:SetShown(not KeystoneLootFrame:IsShown())
            end
        end)

        local btnReset = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnReset:SetSize(200, 24)
        btnReset:SetPoint("LEFT", btnOpen, "RIGHT", 10, 0)
        btnReset:SetText("Reset Window Center")
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            OxedHub.UI:ApplyRedButtonStyle(btnReset)
        end
        btnReset:SetScript("OnClick", function()
            if KeystoneLootFrame then
                KeystoneLootFrame:ClearAllPoints()
                KeystoneLootFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                KeystoneLootFrame:Show()
            end
        end)

        optionsWindow.cursorY = optionsWindow.cursorY - 32

        -- Helper for DB checkboxes
        local function AddDBCheckbox(getVal, setVal, label, tooltip)
            local box = CreateFrame("CheckButton", nil, optionsWindow, "UICheckButtonTemplate")
            box:SetSize(24, 24)
            box:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 16, optionsWindow.cursorY)
            box.text:SetFontObject("GameFontHighlight")
            box.text:SetText(label)

            box:SetScript("OnClick", function(self)
                setVal(self:GetChecked() and true or false)
            end)

            if tooltip then
                box:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(label)
                    GameTooltip:AddLine(tooltip, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                box:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end

            box.Refresh = function()
                box:SetChecked(getVal() == true)
            end
            table.insert(optionsWindow.checks, box)
            optionsWindow.cursorY = optionsWindow.cursorY - 28
            return box
        end

        AddDBCheckbox(
            function()
                local DB = MythicLooter.DB
                return DB and not DB:Get("settings.minimapButton.hide")
            end,
            function(val)
                local DB = MythicLooter.DB
                if DB then
                    DB:Set("settings.minimapButton.hide", not val)
                    if KeystoneLootMinimapButton then
                        KeystoneLootMinimapButton:SetShown(val)
                    end
                end
            end,
            "Show Minimap Button",
            "Displays the MythicLooter hourglass icon on the Minimap."
        )

        AddDBCheckbox(
            function()
                local DB = MythicLooter.DB
                return DB and DB:Get("settings.dropNotification.enable")
            end,
            function(val)
                local DB = MythicLooter.DB
                if DB then DB:Set("settings.dropNotification.enable", val) end
            end,
            "Drop Notifications (Whisper requests)",
            "Shows popup when group members loot an item you have favorited."
        )

        AddDBCheckbox(
            function()
                local DB = MythicLooter.DB
                return DB and DB:Get("settings.lootReminder.enable")
            end,
            function(val)
                local DB = MythicLooter.DB
                if DB then DB:Set("settings.lootReminder.enable", val) end
            end,
            "Loot Spec Reminder before Key Start",
            "Prompts your preferred loot spec before the mythic+ countdown ends."
        )

        AddDBCheckbox(
            function()
                local DB = MythicLooter.DB
                return DB and DB:Get("settings.mythicplusNotification.enable")
            end,
            function(val)
                local DB = MythicLooter.DB
                if DB then DB:Set("settings.mythicplusNotification.enable", val) end
            end,
            "LFG Application Notification",
            "Shows dungeon loot overview when applying to Mythic+ groups."
        )

        AddDBCheckbox(
            function()
                local DB = MythicLooter.DB
                return DB and DB:Get("settings.keystoneTooltip")
            end,
            function(val)
                local DB = MythicLooter.DB
                if DB then DB:Set("settings.keystoneTooltip", val) end
            end,
            "Show Dungeon Loot on Keystone Tooltips",
            "Appends dungeon drop highlights when hovering Mythic+ keys."
        )

        AddDBCheckbox(
            function()
                local DB = MythicLooter.DB
                return DB and DB:Get("settings.itemTooltip")
            end,
            function(val)
                local DB = MythicLooter.DB
                if DB then DB:Set("settings.itemTooltip", val) end
            end,
            "Show Loot Source on Item Tooltips",
            "Shows which dungeon boss or raid encounter drops the item."
        )

        AddDBCheckbox(
            function()
                local DB = MythicLooter.DB
                return DB and DB:Get("settings.keyCommand.CHAT_MSG_PARTY")
            end,
            function(val)
                local DB = MythicLooter.DB
                if DB then DB:Set("settings.keyCommand.CHAT_MSG_PARTY", val) end
            end,
            "Auto-reply to '!key' in Party Chat",
            "Automatically links your current Keystone when someone types !key in party chat."
        )

        optionsWindow:AddNote("Commands: /mythicloot or /ml to open browser | /mythiclooter options\nTip: Click star icons on items to mark them as BiS, Must-Have, or Transmog!")
    end

    optionsWindow:Show()
end

-- ── Slash Commands ──────────────────────────────────────────────────────────
SLASH_MYTHICLOOTER1 = "/mythicloot"
SLASH_MYTHICLOOTER2 = "/mythiclooter"
SLASH_MYTHICLOOTER3 = "/ml"

SlashCmdList["MYTHICLOOTER"] = function(msg)
    local cmd = (msg or ""):lower():trim()
    if cmd == "opt" or cmd == "options" or cmd == "config" or cmd == "settings" then
        ShowOptions()
    else
        if KeystoneLootFrame then
            KeystoneLootFrame:SetShown(not KeystoneLootFrame:IsShown())
        else
            print("|cff9d5db8MythicLooter|r: Loading frame...")
        end
    end
end

-- ── Module Registration ─────────────────────────────────────────────────────
local function RegisterModule()
    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "mythiclooter",
        name     = "MythicLooter",
        version  = "2.18.3",
        updated  = 20261013.9,
        author   = "Oxed",
        category = "groups",
        keywords = { "mythiclooter", "keystoneloot", "m+", "loot", "dungeon", "raid", "bis", "vault", "item" },
        desc     = "Full Mythic+ & Raid loot overview, Best-in-Slot planner, drop reminders, vault tracker, and keystone tooltips.",
        icon     = "Interface\\Icons\\INV_Relics_Hourglass_02",

        defaults = {
            enabled = true,
        },

        OnOptionsShow = function()
            ShowOptions()
        end,

        OnEnable = function()
            if KeystoneLootMinimapButton and KeystoneLootDB and KeystoneLootDB.settings and not KeystoneLootDB.settings.minimapButton.hide then
                KeystoneLootMinimapButton:Show()
            end
        end,

        OnDisable = function()
            if KeystoneLootFrame then KeystoneLootFrame:Hide() end
            if KeystoneLootMinimapButton then KeystoneLootMinimapButton:Hide() end
            if KeystoneLootReminderFrame then KeystoneLootReminderFrame:Hide() end
            if KeystoneLootDropNotificationFrame then KeystoneLootDropNotificationFrame:Hide() end
            if KeystoneLootMythicPlusNotificationFrame then KeystoneLootMythicPlusNotificationFrame:Hide() end
        end,
    })
end

-- Register on load
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        RegisterModule()
    end
end)
