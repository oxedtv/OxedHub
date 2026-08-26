local addonName, OxedHub = ...

-- ---------------------------------------------------------------------------
-- PROFILE SHARE
-- Posts a clickable chat link that other OxedHub users can click to receive a
-- single shared item (the active profile, or one trigger / ring / hub / mix).
--
-- The payload is NOT in the chat message -- chat is capped at 255 characters.
-- The link carries only a short share ID; the sender is recovered from the chat
-- event that delivered it.  When someone clicks the link, their client asks us
-- over the addon channel and we transmit the export string peer-to-peer,
-- chunked and throttled by AceComm.
--
-- Sending is done through the player's own chat edit box.  SendChatMessage is
-- protected in 12.0 and calling it from addon code triggers
-- ADDON_ACTION_BLOCKED, so the addon only pre-fills the box.
-- ---------------------------------------------------------------------------

local Share = {}
OxedHub.Share = Share

local AceComm = LibStub and LibStub:GetLibrary("AceComm-3.0", true)
if AceComm then AceComm:Embed(Share) end

local COMM_PREFIX = "OxedHubShare"   -- addon message prefixes are capped at 16 chars

-- WoW disconnects the client on unknown |H link types, so we ride on
-- "garrmission", which the chat filter permits.
local LINK_TYPE = "garrmission"
local LINK_TAG  = "oxedhub"

-- A single share is meant to be one item, not a whole config dump.
local MAX_SHARE_BYTES = 96 * 1024
-- Ignore repeat requests from the same player inside this window.
local REQUEST_COOLDOWN = 3
-- Drop a half-finished inbound transfer after this long with no progress.
local TRANSFER_TIMEOUT = 60
-- Shared links older than this are pruned at login.
local SHARE_TTL = 7 * 24 * 60 * 60

Share.pendingRequests = {}   -- [senderKey] = { label, requestedAt }
Share.lastRequestAt = {}     -- [requesterKey] = timestamp
Share.linkOwners = {}        -- [shareID] = who posted it, learned from chat

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------

local function Print(msg)
    print("|cff00d9d9Oxed Hub:|r " .. tostring(msg))
end

-- Always compare players including realm, so cross-realm names do not collide.
local function FullPlayerName(name)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName and GetRealmName() or ""):gsub("%s+", "")
    end
    if realm == "" then return name end
    return name .. "-" .. realm
end

local function MyFullName()
    return FullPlayerName(UnitName("player"))
end

local function ShareDB()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.shareCache = OxedHubDB.shareCache or {}
    return OxedHubDB.shareCache
end

-- Toggle with /run OxedHub.Share:ToggleDebug() on BOTH clients.
-- Prints every step of the handshake so a failed transfer can be traced to the
-- exact hop that dropped it.
function Share:ToggleDebug()
    self.debug = not self.debug
    Print("Share debug " .. (self.debug and "|cff88ff88ON|r" or "|cffff6666OFF|r"))
    if self.debug then
        Print("  AceComm loaded: " .. tostring(AceComm ~= nil))
        Print("  Prefix registered: " .. tostring(
            C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered
            and C_ChatInfo.IsAddonMessagePrefixRegistered(COMM_PREFIX)))
        Print("  Initialized: " .. tostring(self.initialized == true))
        local n = 0
        for _ in pairs(ShareDB()) do n = n + 1 end
        Print("  Cached shares: " .. n)
    end
    return self.debug
end

local function Debug(msg)
    if Share.debug then
        print("|cffff9900[Share]|r " .. tostring(msg))
    end
end


-- Cheap Adler-32 style checksum, enough to tell "changed in transit" apart from
-- "was already broken before sending".
-- The combined value must stay inside 32-bit signed range: string.format("%d")
-- on WoW's Lua errors once it goes past 2^31, which silently kills whatever
-- function is building the message.
local function Checksum(str)
    local a, b = 1, 0
    for i = 1, #str do
        a = (a + str:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return (b * 65536 + a) % 2147483647
end

local function NewShareID()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local id = ""
    for _ = 1, 8 do
        local i = math.random(#chars)
        id = id .. chars:sub(i, i)
    end
    return id
end

-- Human-readable summary of what a scope represents.
local SCOPE_LABELS = {
    profile   = "Profile",
    triggers  = "Trigger",
    oxedring  = "Ring",
    hubs      = "Action Hub",
    toymixes  = "Toy Mix",
}

function Share:GetScopeLabel(scope)
    return SCOPE_LABELS[scope] or "Config"
end

-- ---------------------------------------------------------------------------
-- OUTGOING: build a payload, cache it, post the link
-- ---------------------------------------------------------------------------

-- scope/opts are passed straight to UI:BuildScopedExportString.
-- label is what shows inside the chat link.
function Share:CreateShare(scope, opts, label)
    local UI = OxedHub.UI
    if not (UI and UI.BuildScopedExportString) then
        return nil, "Export system unavailable."
    end

    local payload, err = UI:BuildScopedExportString(scope, opts)
    if not payload then
        return nil, err or "Failed to build share data."
    end

    if #payload > MAX_SHARE_BYTES then
        return nil, string.format(
            "Too large to share in chat (%.0f KB, limit %.0f KB). Use the export string instead.",
            #payload / 1024, MAX_SHARE_BYTES / 1024)
    end

    -- Read our own payload back before handing it to anyone.  If it cannot be
    -- decoded here it was never going to work on the other end, and this tells
    -- us the problem is in building the export rather than in transferring it.
    if UI.DecodeExportString then
        local check, decodeErr = UI:DecodeExportString(payload)
        if not check then
            return nil, "Could not build a readable share: " .. tostring(decodeErr)
        end
    end

    local cache = ShareDB()
    local id = NewShareID()
    while cache[id] do id = NewShareID() end

    cache[id] = {
        payload   = payload,
        label     = label or self:GetScopeLabel(scope),
        scope     = scope,
        createdAt = time(),
    }

    return id
end

-- What actually travels over chat: PLAIN TEXT, no hyperlink.
--
-- The 12.0 client silently drops outgoing messages that contain a custom |H
-- hyperlink -- no error, the message simply never arrives.  So the wire format
-- is ordinary text carrying the share code, and the clickable link is rebuilt
-- locally on each receiver by the chat filter below.  A link created client
-- side never crosses the network, so it is never validated or stripped.
local CHAT_MARKER = "[OxedHub]"

function Share:BuildChatText(shareID, label)
    return string.format("%s #%s Sharing: %s", CHAT_MARKER, shareID, label or "Shared Config")
end

-- Matches BuildChatText. The code comes first so an arbitrary label cannot
-- break parsing.
local CHAT_PATTERN = "%[OxedHub%] #(%w+) Sharing: (.+)"

-- The clickable link, built locally for display only.
function Share:BuildLink(shareID, owner, label)
    return string.format(
        "|cff00d9d9|H%s:%s:%s:%s|h[Oxed Hub: %s]|h|r",
        LINK_TYPE, LINK_TAG, shareID, owner or "", label or "Shared Config")
end

-- Open the chat edit box pre-filled with a channel slash command and the link,
-- so the player only has to press Enter.
--
-- We deliberately do NOT call SendChatMessage: it is a protected function in
-- 12.0 and calling it from addon code raises ADDON_ACTION_BLOCKED. The message
-- has to leave through the player's own edit box.
function Share:PostToChat(scope, opts, label, slashPrefix)
    local shareID, err = self:CreateShare(scope, opts, label)
    if not shareID then
        Print("|cffff4444" .. tostring(err) .. "|r")
        return false, err
    end

    local text = (slashPrefix or "") .. self:BuildChatText(shareID, label)

    local active = ChatEdit_GetActiveWindow()
    if active then
        active:SetText(text)
        ChatEdit_ParseText(active, 0)
        active:SetFocus()
        active:HighlightText(0, 0)
        active:SetCursorPosition(active:GetNumLetters())
    else
        ChatFrame_OpenChat(text)
    end

    Print("Ready in your chat box - press |cffffd100Enter|r to post it.")
    return true, shareID
end

-- Channel choices offered by the picker.  These are slash commands rather than
-- SendChatMessage channel constants, because the player's own edit box is what
-- actually sends the message.
local CHANNEL_BUTTONS = {
    { label = "Say",      prefix = "/say " },
    { label = "Party",    prefix = "/party " },
    { label = "Raid",     prefix = "/raid " },
    { label = "Instance", prefix = "/instance " },
    { label = "Guild",    prefix = "/guild " },
}

function Share:ShowChannelPicker(scope, opts, label)
    local f = self.channelPicker
    if not f then
        f = CreateFrame("Frame", "OxedHubSharePicker", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(320, 300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "OxedHubSharePicker")
        if f.TitleText then f.TitleText:SetText("Share to Chat") end

        f.header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.header:SetPoint("TOPLEFT", 16, -32)
        f.header:SetWidth(285)
        f.header:SetJustifyH("LEFT")

        local anchor = f.header
        f.buttons = {}
        for i, def in ipairs(CHANNEL_BUTTONS) do
            local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            btn:SetSize(120, 22)
            if i == 1 then
                btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
            elseif i % 2 == 1 then
                btn:SetPoint("TOPLEFT", f.buttons[i - 2], "BOTTOMLEFT", 0, -6)
            else
                btn:SetPoint("LEFT", f.buttons[i - 1], "RIGHT", 8, 0)
            end
            btn:SetText(def.label)
            btn:SetNormalFontObject("GameFontNormalSmall")
            btn:SetScript("OnClick", function()
                Share:PostToChat(f.scope, f.opts, f.label, def.prefix)
                f:Hide()
            end)
            f.buttons[i] = btn
        end

        local whisperLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        whisperLabel:SetPoint("TOPLEFT", f.buttons[5], "BOTTOMLEFT", 0, -12)
        whisperLabel:SetText("Whisper to:")

        local whisperBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        whisperBox:SetPoint("LEFT", whisperLabel, "RIGHT", 10, 0)
        whisperBox:SetSize(130, 22)
        whisperBox:SetAutoFocus(false)

        -- The payload moves peer-to-peer, so it only transfers while both
        -- players are actually online.
        local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", whisperLabel, "BOTTOMLEFT", 0, -14)
        note:SetPoint("RIGHT", f, "RIGHT", -18, 0)
        note:SetJustifyH("LEFT")
        note:SetSpacing(2)
        note:SetText("|cffffd100Both players must stay online until the transfer finishes.|r\n"
            .. "|cff888888A large profile can take around 30 seconds.|r")
        whisperBox:SetScript("OnEnterPressed", function(box)
            local target = box:GetText()
            if target and target ~= "" then
                Share:PostToChat(f.scope, f.opts, f.label, "/whisper " .. target .. " ")
                box:SetText("")
                f:Hide()
            end
        end)
        f.whisperBox = whisperBox

        self.channelPicker = f
    end

    f.scope, f.opts, f.label = scope, opts, label
    f.header:SetText("Sharing |cffffd100" .. tostring(label) .. "|r\nPick where to post the link:")
    f.whisperBox:SetText("")
    f:Show()
end

-- ---------------------------------------------------------------------------
-- LINK CLICK
-- ---------------------------------------------------------------------------

function Share:OnLinkClicked(shareID, owner)
    if not shareID or shareID == "" then return end

    -- The link is built locally by our chat filter, so it already carries the
    -- sender; fall back to the table the filter fills in.
    if not owner or owner == "" then
        owner = self.linkOwners[shareID]
    end

    -- Our own link: import straight from the local cache, no round trip.
    local myName = MyFullName()
    if owner and myName and owner:lower() == myName:lower() then
        local entry = ShareDB()[shareID]
        if not entry then
            Print("That share has expired.")
            return
        end
        self:PresentImport(entry.payload, myName, entry.label)
        return
    end

    if not owner or owner == "" then
        Print("Could not tell who posted that link. Ask them to share it again.")
        return
    end

    if not AceComm then
        Print("|cffff4444Sharing unavailable: AceComm did not load.|r")
        return
    end

    -- Clicking the link again while a transfer is in flight would queue another
    -- copy of the whole payload, so ignore repeat clicks until it settles.
    local pending = self.pendingRequests[owner:lower()]
    if pending then
        Print("Already waiting on " .. owner .. " - give it a moment.")
        return
    end

    self.pendingRequests[owner:lower()] = { requestedAt = GetTime() }
    Print("Requesting shared config from " .. owner .. "...")
    Debug("sending REQ for " .. shareID .. " to " .. owner)
    self:SendCommMessage(COMM_PREFIX, "REQ:" .. shareID, "WHISPER", owner)

    C_Timer.After(TRANSFER_TIMEOUT, function()
        local pending = self.pendingRequests[owner:lower()]
        if not (pending and pending.requestedAt) then return end
        if (GetTime() - pending.requestedAt) < TRANSFER_TIMEOUT then return end

        -- A transfer that is still arriving (or still recovering lost parts)
        -- is not a silent failure -- leave it alone.
        if self.inbound[owner] then
            Debug("timeout skipped: transfer from " .. owner .. " still in progress")
            return
        end

        self.pendingRequests[owner:lower()] = nil
        Print("|cffff4444No response from " .. owner .. ". They may not have Oxed Hub, or the share expired.|r")
    end)
end

-- ---------------------------------------------------------------------------
-- ADDON CHANNEL
--
-- We do our own chunking rather than handing a 25 KB string to AceComm.
-- AceComm splits at 255 bytes and reassembles blindly: if the server drops a
-- chunk mid-flight -- which it does under load -- the receiver still sees a
-- "complete" message that is silently short.  Numbering every chunk ourselves
-- means a gap is detectable, and we can ask for just the missing pieces.
-- ---------------------------------------------------------------------------

-- Payload bytes per chunk.  Headers add ~20 bytes and AceComm may add an
-- escape byte, so this stays well clear of the 255-byte message limit.
local CHUNK_BYTES = 200
-- Pacing: bursting 130 messages at once is what loses chunks in the first place.
local SEND_INTERVAL = 0.1
local CHUNKS_PER_TICK = 4
-- How long to wait after the last chunk before chasing the gaps.
local GAP_CHECK_DELAY = 1.5
-- Give up rather than asking forever.
local MAX_RESEND_ROUNDS = 5
-- Never put more than this many sequence numbers in one resend request.
local MAX_RESEND_PER_MSG = 20

Share.outbound = {}   -- [requesterKey] = active send
Share.inbound  = {}   -- [senderKey]    = partial receive

function Share:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= COMM_PREFIX or type(message) ~= "string" then return end

    local senderKey = FullPlayerName(sender)
    if not senderKey then
        Debug("dropped: could not resolve sender name")
        return
    end

    local command, rest = message:match("^(%u+):(.*)$")
    if not command then
        Debug("dropped: no command prefix")
        return
    end

    if command == "REQ" then
        Debug("recv REQ from " .. senderKey)
        -- A Lua error in here would otherwise vanish inside the comm callback
        -- and look exactly like "the request was never answered".
        local ok, err = pcall(self.HandleRequest, self, rest, senderKey)
        if not ok then
            Print("|cffff4444Share error while answering " .. senderKey .. ":|r " .. tostring(err))
        end
    elseif command == "HDR" then
        self:HandleHeader(rest, senderKey)
    elseif command == "PRT" then
        self:HandlePart(rest, senderKey)
    elseif command == "RSND" then
        self:HandleResendRequest(rest, senderKey)
    elseif command == "MISS" then
        self.pendingRequests[senderKey:lower()] = nil
        self.inbound[senderKey] = nil
        Print("|cffff4444" .. senderKey .. " no longer has that share.|r")
    end
end

-- ---------------------------------------------------------------------------
-- SENDING
-- ---------------------------------------------------------------------------

function Share:HandleRequest(shareID, requester)
    if not shareID or shareID == "" then return end

    -- Cheap spam guard: one served request per player per few seconds.
    local key = requester:lower()
    local now = GetTime()
    if self.lastRequestAt[key] and (now - self.lastRequestAt[key]) < REQUEST_COOLDOWN then
        Debug("REQ from " .. requester .. " ignored (cooldown)")
        return
    end
    self.lastRequestAt[key] = now

    local entry = ShareDB()[shareID]
    Debug("lookup " .. tostring(shareID) .. " -> "
        .. (entry and ((entry.payload and (#entry.payload .. " bytes")) or "entry with no payload")
            or "NOT FOUND"))

    if not entry or not entry.payload then
        self:SendCommMessage(COMM_PREFIX, "MISS:" .. shareID, "WHISPER", requester)
        return
    end

    self:StartTransfer(shareID, entry, requester)
end

function Share:StartTransfer(shareID, entry, requester)
    local payload = entry.payload
    local label = entry.label or ""
    Debug("StartTransfer: slicing " .. #payload .. " bytes")

    -- Slice once and keep the pieces; a resend then costs nothing to serve.
    local chunks = {}
    for i = 1, #payload, CHUNK_BYTES do
        chunks[#chunks + 1] = payload:sub(i, i + CHUNK_BYTES - 1)
    end
    Debug("StartTransfer: " .. #chunks .. " chunks, sending header")

    self:CancelTransfer(requester)
    self.outbound[requester] = {
        shareID = shareID,
        chunks  = chunks,
        target  = requester,
        cursor  = 1,
    }

    -- Header first: everything the receiver needs to detect a bad transfer.
    self:SendCommMessage(COMM_PREFIX, string.format("HDR:%s:%d:%d:%d:%s",
        shareID, #chunks, #payload, Checksum(payload), label), "WHISPER", requester)

    Debug(("sending %d bytes as %d chunks to %s"):format(#payload, #chunks, requester))
    Print(("Sending |cffffd100%s|r to %s (%d parts)..."):format(label, requester, #chunks))

    self:PumpTransfer(requester)
end

-- Feed chunks out on a timer instead of dumping them all at once.
function Share:PumpTransfer(requester)
    local job = self.outbound[requester]
    if not job then return end

    job.timer = C_Timer.NewTicker(SEND_INTERVAL, function()
        local active = self.outbound[requester]
        if not active then return end

        for _ = 1, CHUNKS_PER_TICK do
            local seq = active.cursor
            if seq > #active.chunks then
                Debug("all chunks sent to " .. requester)
                if active.timer then active.timer:Cancel() end
                active.timer = nil
                -- Keep the sliced payload around briefly to serve resends.
                C_Timer.After(TRANSFER_TIMEOUT, function()
                    if self.outbound[requester] == active then
                        self.outbound[requester] = nil
                    end
                end)
                return
            end
            self:SendCommMessage(COMM_PREFIX, string.format("PRT:%s:%d:%s",
                active.shareID, seq, active.chunks[seq]), "WHISPER", requester, "BULK")
            active.cursor = seq + 1
        end
    end)
end

function Share:CancelTransfer(requester)
    local job = self.outbound[requester]
    if job and job.timer then job.timer:Cancel() end
    self.outbound[requester] = nil
end

-- Re-send only the parts the receiver says it never got.
function Share:HandleResendRequest(body, requester)
    local shareID, list = body:match("^([^:]+):(.*)$")
    local job = self.outbound[requester]
    if not job or job.shareID ~= shareID then
        Debug("resend request for an unknown transfer from " .. requester)
        return
    end

    local n = 0
    for seqStr in tostring(list):gmatch("%d+") do
        local seq = tonumber(seqStr)
        if job.chunks[seq] then
            self:SendCommMessage(COMM_PREFIX, string.format("PRT:%s:%d:%s",
                shareID, seq, job.chunks[seq]), "WHISPER", requester, "BULK")
            n = n + 1
        end
    end
    Debug(("resent %d chunk(s) to %s"):format(n, requester))
end

-- ---------------------------------------------------------------------------
-- RECEIVING
-- ---------------------------------------------------------------------------

function Share:HandleHeader(body, sender)
    -- Only accept data we actually asked for.
    if not self.pendingRequests[sender:lower()] then
        Debug("header from " .. sender .. " ignored (not requested)")
        return
    end

    local shareID, totalStr, lenStr, sumStr, label =
        body:match("^([^:]+):(%d+):(%d+):(%d+):(.*)$")
    if not shareID then
        Print("|cffff4444Received a malformed share from " .. sender
            .. ". They may be on an older Oxed Hub version.|r")
        return
    end

    self.inbound[sender] = {
        shareID  = shareID,
        total    = tonumber(totalStr),
        length   = tonumber(lenStr),
        checksum = tonumber(sumStr),
        label    = label,
        parts    = {},
        got      = 0,
        rounds   = 0,
    }
    Debug(("header from %s: %d chunks, %d bytes"):format(sender, tonumber(totalStr), tonumber(lenStr)))
end

function Share:HandlePart(body, sender)
    local shareID, seqStr, data = body:match("^([^:]+):(%d+):(.*)$")
    if not shareID then return end

    local rx = self.inbound[sender]
    if not rx or rx.shareID ~= shareID then return end

    local seq = tonumber(seqStr)
    if not rx.parts[seq] then
        rx.parts[seq] = data
        rx.got = rx.got + 1
    end

    -- Restart the idle timer on every part, so we only chase gaps once the
    -- stream has actually stopped.
    if rx.gapTimer then rx.gapTimer:Cancel() end
    rx.gapTimer = C_Timer.NewTimer(GAP_CHECK_DELAY, function()
        self:CheckForGaps(sender)
    end)

    if rx.got >= rx.total then
        if rx.gapTimer then rx.gapTimer:Cancel() end
        rx.gapTimer = nil
        self:AssembleTransfer(sender)
    end
end

function Share:CheckForGaps(sender)
    local rx = self.inbound[sender]
    if not rx then return end
    rx.gapTimer = nil

    local missing = {}
    for seq = 1, rx.total do
        if not rx.parts[seq] then
            missing[#missing + 1] = seq
            if #missing >= MAX_RESEND_PER_MSG then break end
        end
    end

    if #missing == 0 then
        self:AssembleTransfer(sender)
        return
    end

    rx.rounds = rx.rounds + 1
    if rx.rounds > MAX_RESEND_ROUNDS then
        Print(("|cffff4444Transfer from %s kept losing data (%d of %d parts missing). Ask them to share it again.|r")
            :format(sender, rx.total - rx.got, rx.total))
        self.inbound[sender] = nil
        self.pendingRequests[sender:lower()] = nil
        return
    end

    Debug(("asking %s to resend %d chunk(s), round %d"):format(sender, #missing, rx.rounds))
    Print(("Recovering %d missing part(s) from %s..."):format(#missing, sender))
    self:SendCommMessage(COMM_PREFIX,
        string.format("RSND:%s:%s", rx.shareID, table.concat(missing, ",")),
        "WHISPER", sender)

    -- Keep chasing until the parts arrive or we run out of rounds.
    rx.gapTimer = C_Timer.NewTimer(GAP_CHECK_DELAY * 2, function()
        self:CheckForGaps(sender)
    end)
end

function Share:AssembleTransfer(sender)
    local rx = self.inbound[sender]
    if not rx then return end

    local ordered = {}
    for seq = 1, rx.total do
        if not rx.parts[seq] then
            -- Still incomplete; let the gap chase continue.
            return
        end
        ordered[seq] = rx.parts[seq]
    end

    local payload = table.concat(ordered)
    self.inbound[sender] = nil
    self.pendingRequests[sender:lower()] = nil

    if #payload ~= rx.length then
        Print(("|cffff4444Transfer from %s was cut short (%d of %d bytes).|r")
            :format(sender, #payload, rx.length))
        return
    end

    local actual = Checksum(payload)
    if actual ~= rx.checksum then
        Print(("|cffff4444Transfer from %s arrived corrupted (checksum %d, expected %d).|r")
            :format(sender, actual, rx.checksum))
        return
    end

    Debug(("assembled %d bytes from %s"):format(#payload, sender))
    self:PresentImport(payload, sender, rx.label)
end

-- ---------------------------------------------------------------------------
-- IMPORT
-- ---------------------------------------------------------------------------

function Share:PresentImport(payload, sender, label)
    local UI = OxedHub.UI
    if not (UI and UI.DecodeExportString and UI.ShowImportConfirm) then
        Print("|cffff4444Import system unavailable.|r")
        return
    end

    local data, err = UI:DecodeExportString(payload)
    if not data then
        Print("|cffff4444Could not read the shared config: " .. tostring(err) .. "|r")
        return
    end

    -- Never apply automatically. ShowImportConfirm lists the contents and makes
    -- the user confirm, which matters because triggers can send chat messages,
    -- fire emotes and create macros.
    data.sharedBy = sender
    data.sharedLabel = label
    UI:ShowImportConfirm(data)
end

-- ---------------------------------------------------------------------------
-- MAINTENANCE
-- ---------------------------------------------------------------------------

function Share:PruneExpiredShares()
    local cache = ShareDB()
    local now = time()
    for id, entry in pairs(cache) do
        if type(entry) ~= "table" or not entry.createdAt or (now - entry.createdAt) > SHARE_TTL then
            cache[id] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- WIRING
-- ---------------------------------------------------------------------------

-- Watch chat for our links so we know who posted each share ID.  The link
-- itself deliberately carries no sender (see BuildLink).
local WATCHED_CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
}

-- Rewrite our plain-text share announcements into a clickable link.  This runs
-- on the receiving client only, so the link never crosses the network and is
-- never subject to the outgoing hyperlink filtering that drops custom links.
function Share:RegisterChatFilters()
    local function filter(_, _, message, author, ...)
        if type(message) ~= "string" then
            return false, message, author, ...
        end

        local shareID, label = message:match(CHAT_PATTERN)
        if not shareID then
            return false, message, author, ...
        end

        local owner = FullPlayerName(author) or author
        Share.linkOwners[shareID] = owner

        local rewritten = Share:BuildLink(shareID, owner, label) .. " |cff888888(click to import)|r"
        return false, rewritten, author, ...
    end

    for _, event in ipairs(WATCHED_CHAT_EVENTS) do
        ChatFrame_AddMessageEventFilter(event, filter)
    end
end

function Share:Initialize()
    if self.initialized then return end
    self.initialized = true

    if AceComm then
        self:RegisterComm(COMM_PREFIX)
    end

    self:PruneExpiredShares()
    self:RegisterChatFilters()

    -- Intercept clicks on our links before Blizzard tries to resolve them as a
    -- real garrison mission.
    hooksecurefunc("SetItemRef", function(link)
        if type(link) ~= "string" then return end
        local shareID, owner = link:match("^" .. LINK_TYPE .. ":" .. LINK_TAG .. ":(%w+):?(.*)$")
        if shareID then
            Share:OnLinkClicked(shareID, owner)
        end
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    Share:Initialize()
end)
