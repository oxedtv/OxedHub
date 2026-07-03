-- ChatDispatcher.lua
-- Loaded BEFORE any libraries (AceDB, etc.) to create a clean, untainted
-- execution context for SendChatMessage, DoEmote, and Cooldown:SetCooldown.
--
-- NomNom works because its callstack never touches library code.
-- OxedHub goes through AceDB which introduces taint.  By creating this
-- dispatcher frame before any library loads, the OnUpdate handler runs
-- in a clean context that Blizzard's taint system does not block.
--
-- In WoW 12.0 (Midnight) the cooldown start/duration from C_Spell.GetSpellCooldown
-- are "secret values" that Cooldown:SetCooldown will only accept during UNTAINTED
-- execution. Doing it here (pre-library, untainted) lets us drive a hidden
-- Cooldown widget whose OnCooldownDone tells us exactly when a spell is ready.

local addonName, OxedHub = ...

local dispatchFrame = CreateFrame("Frame")
local chatQueue = {}
local emoteQueue = {}

-- Process queued messages on the next frame render (clean callstack)
dispatchFrame:SetScript("OnUpdate", function(self)
    -- Process chat messages
    if #chatQueue > 0 then
        local entry = table.remove(chatQueue, 1)
        if entry.target then
            SendChatMessage(entry.msg, entry.ch, nil, entry.target)
        else
            SendChatMessage(entry.msg, entry.ch)
        end
    end

    -- Process emotes
    if #emoteQueue > 0 then
        local entry = table.remove(emoteQueue, 1)
        if entry.isWhisper and entry.target then
            SendChatMessage("/" .. entry.emote:lower(), "WHISPER", nil, entry.target)
        else
            DoEmote(entry.emote)
        end
    end

    -- Stop ticking when nothing is queued
    if #chatQueue == 0 and #emoteQueue == 0 then
        self:Hide()
    end
end)
dispatchFrame:Hide() -- Start hidden (OnUpdate only fires when shown)

-- Global dispatch functions that OxedHub modules call
-- These just queue the action; the actual API call happens
-- in OnUpdate which has a clean, untainted callstack.
function OxedHub_DispatchChat(msg, channel, target)
    table.insert(chatQueue, { msg = msg, ch = channel, target = target })
    dispatchFrame:Show()
end

function OxedHub_DispatchEmote(emoteName, isWhisper, targetName)
    table.insert(emoteQueue, { emote = emoteName, isWhisper = isWhisper, target = targetName })
    dispatchFrame:Show()
end
