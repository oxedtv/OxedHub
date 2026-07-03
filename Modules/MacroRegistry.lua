-- MacroRegistry.lua - Internal Macro System for OxedHub
-- Stores and executes macros internally without creating real WoW macros.
-- No 255-char limit, no macro UI clutter.

local addonName, OxedHub = ...
local MacroRegistry = {}
OxedHub.MacroRegistry = MacroRegistry

-- Ensure saved variable table exists
function MacroRegistry:Init()
    if not OxedHub.db.profile.internalMacros then
        OxedHub.db.profile.internalMacros = {}
    end
end

-- Get all internal macros
function MacroRegistry:GetMacros()
    return OxedHub.db.profile.internalMacros or {}
end

-- Add or update a macro
function MacroRegistry:SaveMacro(name, data)
    local macros = self:GetMacros()
    macros[name] = {
        slots = data.slots or {},     -- { {type="toy"/"spell", id=123}, ... }
        actions = data.actions or {}, -- { sound=..., animation=..., emote=..., chat=... }
    }
end

-- Delete a macro
function MacroRegistry:DeleteMacro(name)
    local macros = self:GetMacros()
    if macros[name] then
        macros[name] = nil
        return true
    end
    return false
end

-- Rename a macro
function MacroRegistry:RenameMacro(oldName, newName)
    local macros = self:GetMacros()
    if not macros[oldName] then return false end
    if macros[newName] then return false end -- prevent overwrite

    macros[newName] = macros[oldName]
    macros[oldName] = nil
    return true
end

-- Execute a macro by name
function MacroRegistry:RunMacro(name)
    local macros = self:GetMacros()
    local macro = macros[name]
    if not macro then
        print("|cffff0000OxedHub:|r Mix not found: " .. tostring(name))
        return
    end

    -- From slash commands we can only run non-protected actions.
    -- Toys/spells require clicking the secure Run button in the UI.
    self:ExecuteMix(macro)
end

-- Execute a mix data table directly (slots + actions)
-- NOTE: This must be called from a secure execution path (button click, keybind)
function MacroRegistry:ExecuteMix(data)
    if type(data) ~= "table" then return end

    -- Execute slots (toys then spells)
    -- NOTE: protected APIs require secure execution path (button click)
    if data.slots then
        for _, slot in ipairs(data.slots) do
            if slot then
                if slot.type == "toy" then
                    if PlayerHasToy(slot.id) then
                        local ok, err = pcall(function() C_ToyBox.UseToyByItemID(slot.id) end)
                        if not ok then
                            print("|cffff0000OxedHub:|r Cannot use toy from this context. Click the Run button instead.")
                        end
                    end
                elseif slot.type == "spell" then
                    local spellInfo = C_Spell.GetSpellInfo(slot.id)
                    if spellInfo and spellInfo.name then
                        local ok, err = pcall(function() CastSpellByName(spellInfo.name) end)
                        if not ok then
                            print("|cffff0000OxedHub:|r Cannot cast spell from this context. Click the Run button instead.")
                        end
                    end
                end
            end
        end
    end

    -- Execute actions
    local actions = data.actions or {}

    if actions.emote then
        DoEmote(actions.emote:upper())
    end

    if actions.chat then
        local chat = OxedHub.db.profile.chatTemplates[actions.chat]
        if chat and chat.channel and chat.text then
            local channel = chat.channel:lower()
            local text = chat.text
            if channel == "say" then
                SendChatMessage(text, "SAY")
            elseif channel == "yell" then
                SendChatMessage(text, "YELL")
            elseif channel == "emote" then
                SendChatMessage(text, "EMOTE")
            elseif channel == "party" then
                SendChatMessage(text, "PARTY")
            elseif channel == "guild" then
                SendChatMessage(text, "GUILD")
            elseif channel == "raid" then
                SendChatMessage(text, "RAID")
            else
                -- Try as a channel number or name
                SendChatMessage(text, channel:upper())
            end
        end
    end

    if actions.sound then
        if OxedHub.Sounds and OxedHub.Sounds.Play then
            OxedHub.Sounds:Play(actions.sound)
        end
    end

    if actions.animation then
        if OxedHub.Animations and OxedHub.Animations.Play then
            OxedHub.Animations:Play(actions.animation)
        end
    end
end

-- List macros (returns sorted names)
function MacroRegistry:GetMacroNames()
    local macros = self:GetMacros()
    local names = {}
    for name in pairs(macros) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Print macro list to chat
function MacroRegistry:ListMacros()
    local names = self:GetMacroNames()
    if #names == 0 then
        print("|cff00ff00OxedHub:|r No saved mixes yet.")
        return
    end

    print("|cff00ff00OxedHub Mixes:|r")
    for i, name in ipairs(names) do
        print("  " .. i .. ". " .. name)
    end
end

-- Slash command handler
function MacroRegistry:SlashHandler(msg)
    local args = {}
    for word in string.gmatch(msg, "%S+") do
        table.insert(args, word)
    end
    local cmd = args[1] and args[1]:lower()

    if cmd == "run" then
        local macroName = args[2]
        if macroName then
            -- Rebuild name from remaining args if it had spaces
            if #args > 2 then
                macroName = table.concat(args, " ", 2)
            end
            self:RunMacro(macroName)
        else
            print("|cffff0000OxedHub:|r Usage: /oxedhub mix run <name>")
        end
    elseif cmd == "list" then
        self:ListMacros()
    elseif cmd == "delete" or cmd == "del" then
        local macroName = args[2]
        if macroName then
            if #args > 2 then
                macroName = table.concat(args, " ", 2)
            end
            if self:DeleteMacro(macroName) then
                print("|cff00ff00OxedHub:|r Deleted mix: " .. macroName)
                -- Refresh UI if open
                if OxedHub.Toys and OxedHub.Toys.RefreshSavedMixesList then
                    OxedHub.Toys:RefreshSavedMixesList()
                end
            else
                print("|cffff0000OxedHub:|r Mix not found: " .. macroName)
            end
        else
            print("|cffff0000OxedHub:|r Usage: /oxedhub mix delete <name>")
        end
    else
        print("|cff00ff00OxedHub Mix Commands:|r")
        print("  |cff00ffff/oxedhub mix list|r - List all mixes")
        print("  |cff00ffff/oxedhub mix run <name>|r - Run a mix")
        print("  |cff00ffff/oxedhub mix delete <name>|r - Delete a mix")
    end
end

-- Register slash command
SLASH_OXEDHUB_MIX1 = "/oxedhubmix"
SlashCmdList["OXEDHUB_MIX"] = function(msg)
    if OxedHub.MacroRegistry then
        OxedHub.MacroRegistry:SlashHandler(msg)
    end
end
