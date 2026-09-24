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
        version = "2.3.83",
        important = true,
        lines = {
            { "FIXED", "The one lag spike OxedHub was still causing itself: on a raid pull the game sends twenty and more proc glow events in a single frame, and Action Hub redrew every node for each one. Frames of 29 ms, three quarters of them OxedHub, are now one redraw a frame." },
            { "CHANGED", "Action Hub asks the game far less: a cooldown change no longer re-checks every node's proc glow, and the greying of unusable icons happens at most ten times a second instead of on every event." },
            { "CHANGED", "Rules remember each spell's name instead of asking the game for it again on every cast, for every rule. That alone was 17 KB of memory per spell you cast." },
            { "CHANGED", "Buff Reminder finds your food buff by name in one read rather than walking all forty buffs, and the aura scan reuses its table instead of making a new one on every aura change." },
            { "CHANGED", "Shattersight only copies your bags when you actually have Enchanting; without it there is nothing to disenchant, and the copy cost 150 KB every time your bags changed." },
            { "FIXED", "Auto Gossip raised an error when the game kept an NPC's identity secret." },
        },
    },
    {
        version = "2.3.82",
        lines = {
            { "FIXED", "Attributes: the stats box on screen no longer raises an error in combat, where the game hides stat values. It keeps the last figures until they can be read again." },
            { "FIXED", "Cursor: the pointer drawn while the right button turns the camera is the size of the game's own pointer again, instead of a much bigger hand." },
            { "ADDED", "Cursor: untick Show the pointer while turning the camera and everything hides while you turn it, as it does without the module. /oxcursor prints the pointer's size figures." },
        },
    },
    {
        version = "2.3.81",
        important = true,
        lines = {
            { "ADDED", "Cursor: every theme is drawn in layers now. Frost drops turning snowflakes, Arcane opens runic rings, Lightning cracks real forked bolts, Nature sheds leaves that turn to autumn, Void hangs dark smoke and Holy lifts golden light." },
            { "ADDED", "Cursor: five new themes. Fel burns green, Blood falls in heavy drops, Bubbles rise and pop, Fairy leaves a glittering dust, and Windows 95 brings back the old pointer trails." },
            { "ADDED", "Cursor: a wider options window with a tab for every theme. Each theme keeps its own glow, shadow and trail, and Reset this theme puts one back as it was." },
            { "ADDED", "Cursor: choose how the pointer looks while the right button steers (arrow, ghost or glow), set the game's own pointer size, and how far the mouse moves before the camera turns. Both game settings go back as they were when you pick Game or switch the module off." },
            { "CHANGED", "Module windows use the modern frame of the Pick Sound window, and the Modules page has a soft gold line under its tabs." },
            { "ADDED", "Performance report (/oxprofile): every lag spike now says why it happened: OxedHub, another addon by name, a memory cleanup, a busy scene or the game itself. It lists the busiest addons, the events of that frame, each addon's average cost, and which parts of OxedHub make the most garbage." },
            { "FIXED", "Action Hub does far less work on every pass: nothing is redrawn that did not change, and hidden hubs are skipped." },
            { "FIXED", "Cursor: sparks no longer shoot across the screen as long streaks after a fast flick of the mouse." },
        },
    },
    {
        version = "2.3.80",
        important = true,
        lines = {
            { "ADDED", "Cursor module (Modules, Interface): a glow around your hand and a trail of sparks behind the pointer, so it is never lost in a fight. Choose whether the glow sits on the hand or the tip, pick its colour, and nudge it into place." },
            { "ADDED", "Cursor themes: Fire burns and smokes even while the mouse rests, Meteor lays a white-hot tail along the exact path and sheds falling debris, and Frost, Arcane, Lightning, Nature, Shadow and Holy each move their own way. Custom follows your class colour, your own colour or a rainbow." },
            { "ADDED", "Cursor: rest the mouse and the sparks spiral around the pointer instead of trailing behind it, and the wait before they start is yours to set. A ring spreads from every click, shaking the mouse flares the glow up to find it, and the pointer stays drawn where it froze while the right button steers." },
            { "ADDED", "Attributes: show your stats on screen. Drag the box anywhere, right-click it to tick the stats it shows, and set each target from the same place while the numbers move. Lock it, scale it, or show it only in combat. Type /oxstats." },
            { "FIXED", "Copy Chat no longer searches every frame in the game when it looks for a Chattynator window, which froze the game for several seconds." },
            { "FIXED", "Action Hub redraws its cooldowns once a frame rather than once per event, and potion rules no longer scan your bags on every cast." },
        },
    },
    {
        version = "2.3.79",
        lines = {
            { "ADDED", "Search on the Modules page: type in the box at the top and the cards narrow as you go. It looks at names, descriptions and hidden keywords, so \"repair\" finds Auto Vendor and \"interrupt\" finds KickBar." },
            { "ADDED", "Favourite modules: click the star on a card. Favourites come first on every tab, and get a Favorites tab of their own." },
        },
    },
    {
        version = "2.3.78",
        important = true,
        lines = {
            { "ADDED", "Teleports module (Modules, Travel & Tools): a button your teleports fly out of -- hearthstones, your class's own teleports, the portals you open for the group, teleport toys, what is in your bags and the cloak or ring you are wearing. It finds them itself: a spell only when you know it, a toy only when you own it, an item only while you carry it." },
            { "ADDED", "Teleports: each group flies out its own way -- right, left, up or down -- and groups sent the same way stack behind each other. Left-click an icon to travel, right-click to put it away. Type /tp." },
            { "ADDED", "Attributes: stat targets. Set a target per secondary for the specialisation you are playing, and the bar shows how far along you are and how much more rating it would take, with diminishing returns already counted. Without a target the bars compare your secondaries with each other." },
            { "ADDED", "The window now dresses up for the holiday running in the game, with a line at the foot naming it and its dates -- click it for the calendar, or the scroll beside it for the Wowhead guide. Switch it off in Settings, Ring and Display." },
            { "FIXED", "Attributes: the new bars sat on the line underneath them." },
        },
    },
    {
        version = "2.3.77",
        important = true,
        lines = {
            { "ADDED", "Auto Queue module (Modules, General): answers Dungeon Finder role checks and accepts \"Your group is ready\" for you, confirms Group Finder sign-ups with your roles, and signs you up when you double-click a listing. Hold Shift while signing up to write a note." },
            { "ADDED", "Auto Queue: a role picker above the Group Finder to queue as several roles or one your spec is not, saved per character. Groups that declined you show red, delisted or full ones orange, and you may apply again. Listing tooltips show how old a group is, and your sign-up note is kept. Type /aq for the status." },
            { "ADDED", "Auto Vendor: Export and Import buttons for the sell list -- share it with a friend or copy it to another account. Import adds to your list and keeps the higher quality limit." },
        },
    },
    {
        version = "2.3.76",
        important = true,
        lines = {
            { "ADDED", "Buff Reminder 1.2: a missing food, flask, rune or weapon oil shows every matching item in your bags as its own icon, with its count and stat -- click one to use it. Oil is offered per hand. Missing pets show each pet you can call plus Revive Pet; healthstones, low durability and, on a ready check, Soulwell and Refreshment Table are covered too." },
            { "ADDED", "Buff Reminder: choose the icon size with a slider, and show names under the icons." },
            { "ADDED", "Auto Quest: when a quest offers a choice, the reward worth the most gold gets a coin, and rewards above your item level get a green +N ilvl arrow." },
            { "ADDED", "Auto Vendor: bind a key (Key Bindings, Oxed Hub) and press it over any item to add it to the sell list, or take it off." },
            { "ADDED", "A What's New button at the top right of the Oxed Hub window opens these notes for every version." },
            { "CHANGED", "Copy Chat works with Chattynator: the button sits on its windows and opens its copy window." },
            { "FIXED", "Auto Vendor sold a better copy of an item on your list (an epic when you added the blue). The list now sells only at the quality you added, or lower." },
            { "FIXED", "Buff Reminder showed food as missing with Well Fed up, and a runeforge as missing on some weapons." },
            { "FIXED", "The \"protected function AddAuraSound\" error after each update. OxedHub no longer tries a call the game refuses." },
        },
    },
    {
        version = "2.3.75",
        important = true,
        lines = {
            { "ADDED", "Buff Reminder module (Modules, Combat): a row of icons for what is missing -- the group buff your class gives, your own poisons, shields, imbues, forms and runeforge, your pet, and food, flask, rune and weapon oil in instances. Click an icon to cast it or use the item." },
            { "ADDED", "Buff Reminder counts nearby group members missing your buff (names in the tooltip), warns about buffs with under five minutes left, finds flasks and runes in your bags on its own, and shows everything for 30 seconds on a ready check." },
            { "ADDED", "The bar hides in combat and never guesses from hidden combat data. Shift+drag an icon to move it." },
        },
    },
    {
        version = "2.3.74",
        lines = {
            { "ADDED", "Performance recordings are kept through /reload and logout -- the last ten -- so a lag can be looked at, and a report copied, later. Step through them with the button at the top right of the Performance window." },
            { "CHANGED", "The small performance monitor now sits below your bags and other windows instead of covering them, and its recording light is a clean dot inside the ring." },
        },
    },
    {
        version = "2.3.73",
        lines = {
            { "FIXED", "Two errors from 2.3.72: KickBar threw one every time you took a target that was not casting, and the performance monitor threw one while naming a timer during combat." },
        },
    },
    {
        version = "2.3.72",
        important = true,
        lines = {
            { "ADDED", "Performance monitor: how long every part of OxedHub takes and what ran during each lag spike, with a small on-screen readout. Ctrl+click the minimap button, or type /oxprofile." },
            { "ADDED", "Attributes: diminishing returns on each secondary stat (asked of the game, so it follows every patch), a snapshot to compare before and after a gear change, global cooldown, effective health, live skyriding speed and your weakest gear slot." },
            { "FIXED", "A short hitch when casting spells, caused by the toy usage counter. KickBar and Attributes no longer run every frame when they have nothing to show." },
        },
    },
    {
        version = "2.3.71",
        important = true,
        lines = {
            { "FIXED", "Spell Cast Success rules for a spell that leaves a buff -- a defensive cooldown, for example -- no longer play their sound again on every other spell you cast while that buff is up." },
        },
    },
    {
        version = "2.3.70",
        important = true,
        lines = {
            { "ADDED", "Auto Quest (accepts and hands in quests when you talk to NPCs) and Auto Gossip (picks an NPC's only menu option), both off until you switch them on. Copy Chat's button can now be moved." },
            { "FIXED", "KickBar no longer shows on casts that cannot be interrupted, and finds warlock pet interrupts. Holding Shift to skip a module is now a switch in its Options, off by default." },
        },
    },
    {
        version = "2.3.69",
        important = true,
        lines = {
            { "CHANGED", "Modules (Beta) are now off until you switch them on. Any module you had not turned on yourself was switched off once -- open Modules to turn back on the ones you use." },
            { "ADDED",   "Chat Filter (an unlimited ignore list, word filters and spam blocking), Missing Gems, a sell list and a Yes / No check for Auto Vendor and Auto Banker, and Auto Confirm to choose which game popups to skip." },
        },
    },
    {
        version = "2.3.67",
        important = true,
        lines = {
            { "ADDED",   "Three more Modules (Beta): Attributes, an Attributes tab on your character window with live movement speed and the stats the sheet leaves out. Auto Banker, which puts your reagents away and restocks whatever you already keep in the bank. Copy Chat, which opens any chat window as text you can copy -- set a key for it under Key Bindings, OxedHub." },
            { "FIXED",   "Repeating sounds: Bloodlust no longer replays itself when the game hides aura data mid-fight, and a channelled spell counts as one cast instead of one per tick." },
        },
    },
    {
        version = "2.3.66",
        important = true,
        lines = {
            { "ADDED",   "Modules (Beta): a new page of small tools built into OxedHub, sorted into categories and switched on and off from their cards. We're testing it live, so tell us what you think." },
            { "ADDED",   "KickBar: a kick alert on the enemy nameplate when your interrupt is ready. It now greys out while the interrupt is on cooldown, even in combat." },
            { "ADDED",   "Auto Vendor: sells your junk and repairs your gear whenever you open a vendor, using guild funds first if you want. Hold Shift to skip a visit." },
            { "ADDED",   "Auto Delete: types the confirmation word for you when you destroy an item. You still press Accept yourself." },
            { "CHANGED", "About has moved to the ? button next to the close button." },
        },
    },
    {
        version = "2.3.65",
        lines = {
            { "ADDED",   "Sort toys by how often you use them: a new option in ToyBoxes > Settings that puts the ones you actually reach for at the front." },
            { "ADDED",   "Wish List: a box holding every toy you have not collected yet, to browse and hunt down. Switch it off in the same settings if you would rather not see it." },
            { "CHANGED", "Toy use is counted from the toy going off, so it counts wherever you used it from -- the grid, the dock, a quick slot, a macro or a keybind." },
        },
    },
    {
        version = "2.3.64",
        lines = {
            { "FIXED",   "A huge pile of blocked-action errors in the log: the enemy buff watcher kept asking the client to register a sound it will not allow, once per spell per unit, on every arena and target change. It now asks once and remembers the answer." },
            { "FIXED",   "Minimising the toy dock during combat did nothing and logged an error. It now minimises the moment combat ends, and says so." },
            { "CHANGED", "What's New shows both packs, and the front page carries the Gaming Pack link." },
        },
    },
    {
        version = "2.3.63",
        important = true,
        lines = {
            { "ADDED",   "OxedHub Gaming Pack is out: a second pack of sounds and animations to sit alongside the Meme Pack. Both are on the front page, click either logo for its CurseForge link." },
            { "ADDED",   "An animation can now run for as long as the buff lasts instead of playing once -- tick Repeat while buff is up beside the animation." },
            { "CHANGED", "A buff that keeps refreshing itself plays continuously, and the animation clears the instant the buff drops." },
            { "CHANGED", "The front page now lists what actually changed in the latest releases, rather than features from long ago." },
        },
    },
    {
        version = "2.3.60",
        lines = {
            { "ADDED",   "Repeat while buff is up: an aura trigger can keep its animation running for as long as the buff lasts, and it disappears the moment the buff does." },
            { "CHANGED", "A buff refreshing itself no longer restarts the animation, so something you keep topped up plays continuously." },
            { "CHANGED", "Trinket Used is now Trinket Used (on-use), and a trinket that fires on its own says so: the game reports nothing an addon can react to." },
        },
    },
    {
        version = "2.3.59",
        lines = {
            { "ADDED",   "Potion and Trinket triggers: react when you drink a potion or one of your trinkets goes off, and pick exactly which ones count." },
            { "ADDED",   "Every picked item gets its own sound and animation -- click an item and the Actions section edits that one." },
            { "CHANGED", "Picked items are highlighted and refresh live, and a trinket you take off is dropped from the rule." },
            { "FIXED",   "Macros on an action hub never showed their cooldown." },
        },
    },
    {
        version = "2.3.58",
        lines = {
            { "ADDED",   "Restrict a trigger to specific specialisations, so a rule set up for healing stays quiet on your damage spec." },
            { "ADDED",   "Specialisations are listed by their real names -- Blood, Frost, Unholy -- because two of them can share a role but need different rules." },
            { "CHANGED", "The Zones & Groups tab is now Conditions: zone, group size and specialisation all live there." },
            { "FIXED",   "The Sound priority field stayed on screen over the Conditions and Tips tabs." },
        },
    },
    {
        version = "2.3.57",
        lines = {
            { "FIXED",   "Freezes and stutter, most noticeably while typing in the trigger search: the font resizer was walking every row's whole frame tree on every keystroke, usually to set each font to the size it already was." },
            { "FIXED",   "Action hub settings were rebuilt from scratch on every single lookup, a hundred and twenty times over across the addon." },
            { "ADDED",   "Undo for a deleted trigger: its row stays as a greyed placeholder until you reload." },
            { "ADDED",   "Control what happens when several triggers fire at once -- skip duplicates, let the more important rule win, or fade the previous sound." },
            { "CHANGED", "A refused aura sound is remembered, so it stops logging the same blocked call on every login. Settings has a button to test it again." },
        },
    },
    {
        version = "2.3.56",
        important = true,
        lines = {
            { "FIXED",   "The random toy and random hearthstone buttons did nothing for anyone who casts on key release." },
            { "FIXED",   "Toy boxes opened full of question marks; icons are now remembered and appear from the first frame." },
            { "ADDED",   "Closing a toy box locks it again, and a warning shows while unlocked, so toys never quietly stop working." },
            { "ADDED",   "Trigger search now matches what a rule does -- its sound, animation, toy, chat text, zones and more." },
            { "ADDED",   "Spell Cast Start: react the moment a cast begins instead of when it lands." },
            { "ADDED",   "An info icon beside the event picker explains the selected event in depth." },
            { "ADDED",   "Zones tab is now Zones & Groups: restrict a trigger to solo, party or raid." },
            { "ADDED",   "Trigger history: a Log column showing what fired today, and a full activity page." },
            { "ADDED",   "Optional backup before an import merges into a profile, with one-click restore." },
            { "CHANGED", "Faster and lighter: saved data is a quarter of its old size and login parses far less." },
        },
    },
    {
        version = "2.3.46",
        lines = {
            { "ADDED",   "Preview button in the trigger list: every animation on screen at once, labelled with the rule and what makes it fire." },
            { "ADDED",   "Drag a tile to place that animation, with an optional screen grid and snapping." },
            { "ADDED",   "Change a tile's sound or animation without leaving the preview, or right-click to play it." },
            { "FIXED",   "The animation preview in the picker vanished a moment after you hovered a row." },
        },
    },
    {
        version = "2.3.45",
        lines = {
            { "ADDED",   "The trigger list flags two rules that reuse one sound, on the rule and on its category heading." },
            { "ADDED",   "Right-click a trigger for open, enable, duplicate, copy to another profile, share and delete." },
            { "ADDED",   "A sound warning can be ignored per rule, from that same right-click menu." },
        },
    },
    {
        version = "2.3.44",
        lines = {
            { "ADDED",   "Move Mode unlocks several action hubs at once, so each hub's nodes can be dragged on their own." },
            { "FIXED",   "Only the active hub reacted to a node drag -- a second bar could just be shoved around whole." },
        },
    },
    {
        version = "2.3.43",
        lines = {
            { "FIXED",   "Reordering toy boxes threw away the previous arrangement, sending another box back to its old spot." },
            { "ADDED",   "A green line shows where a dragged toy box will land before you let go." },
        },
    },
    {
        version = "2.3.42",
        lines = {
            { "ADDED",   "Triggers are grouped by category, and a group folds away with a click." },
            { "ADDED",   "New rules are named after their event instead of \"New Trigger\"." },
            { "ADDED",   "A rule with no actions is dimmed and marked, so dead experiments stand out." },
            { "FIXED",   "Trigger repairs on load had never run -- rules could share one set of conditions." },
            { "CHANGED", "The zone column stays blank unless a rule is actually restricted." },
        },
    },
    {
        version = "2.3.41",
        lines = {
            { "ADDED",   "Macro Helper in both macro editors: templates, conditions and commands, inserted at the cursor." },
            { "ADDED",   "Templates use your own class ability -- Counterspell for a mage, Pummel for a warrior." },
            { "FIXED",   "The macro editor would not scroll up." },
            { "FIXED",   "Long macros drew their text twice, offset." },
            { "FIXED",   "Self Aura flooded the error log with blocked calls." },
        },
    },
    {
        version = "2.3.39",
        lines = {
            { "ADDED",   "Thirty-five toy categories with descriptions, filled from the toys you own." },
            { "ADDED",   "A My Mixes section in ToyBoxes, in the panel and the floating dock." },
            { "ADDED",   "Hide button on a box, and Copy on each Debug entry alongside Copy All." },
            { "FIXED",   "Clicking a toy in the ToyBoxes grid did nothing at all." },
            { "FIXED",   "Shipped categories could not be dragged to reorder them." },
            { "FIXED",   "The Debug tab stayed empty while BugSack showed the same errors." },
            { "CHANGED", "Locked uses a tile, unlocked moves it -- in both the panel and the dock." },
            { "CHANGED", "The Debug list marks what appeared since your last visit." },
        },
    },
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

local function VersionParts(version)
    local major, minor, patch = tostring(version or ""):match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then return nil end
    return tonumber(major), tonumber(minor), tonumber(patch)
end

-- Opening on every release is noise: most are a fix or two. The window waits
-- until this many patch versions have gone by, so it appears with something
-- worth reading rather than interrupting after each small update.
local PATCH_GAP = 5

function WhatsNew:ShouldShow()
    local db = Store()
    if not db or db.whatsNewDisabled then return false end

    local current = CurrentVersion()
    if VersionValue(current) <= VersionValue(db.whatsNewSeenVersion) then
        return false
    end

    -- Nothing seen yet: a fresh install gets it once.
    local seenMajor, seenMinor, seenPatch = VersionParts(db.whatsNewSeenVersion)
    if not seenMajor then return true end

    local major, minor, patch = VersionParts(current)
    if not major then return true end

    -- A new major or minor is a real release, not a patch, and is shown
    -- regardless of how recently the player last read the notes.
    if major ~= seenMajor or minor ~= seenMinor then return true end

    if (patch - seenPatch) >= PATCH_GAP then return true end

    -- An entry can ask to be shown anyway, for the occasional patch that
    -- changes something the player has to know about.
    for _, release in ipairs(self.RELEASES) do
        if release.important
            and VersionValue(release.version) > VersionValue(db.whatsNewSeenVersion) then
            return true
        end
    end

    return false
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

-- Both packs, in the order they came out. Described in a table because the
-- panel below is now built twice, and two hand-written copies of it is how the
-- second one ends up with the first one's link.
local PACKS = {
    {
        key = "meme",
        title = "Oxed Hub Meme Pack",
        texture = MEMEPACK_TEXTURE,
        url = MEMEPACK_URL,
        button = "Get the Meme Pack",
        body = "Updated 2-3 times a week with new animations and sounds. "
            .. "Install it alongside Oxed Hub and everything new shows up in your pickers automatically.",
    },
    {
        key = "gaming",
        title = "Oxed Hub Gaming Pack",
        texture = "Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\OxedHubGamingPack.png",
        url = "https://www.curseforge.com/wow/addons/oxedhub-gaming-pack",
        button = "Get the Gaming Pack",
        body = "Sounds and animations from the games everyone knows. "
            .. "A separate pack, installed the same way, and it fills the same pickers.",
    },
}

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
    -- Above the main window, whose parts reach level 500 in DIALOG: it now
    -- opens from the main window's What's New button and must not sit behind it.
    f:SetFrameStrata("FULLSCREEN_DIALOG")
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

    -- The packs flanking the addon's own mark.
    --
    -- There are three things a player can install now, and the header showed
    -- one of them. Small, and to the sides, so the heading below still reads
    -- as the title of the window rather than competing with them.
    local packMarks = { PACKS[1], PACKS[2] }
    for index, pack in ipairs(packMarks) do
        local mark = f:CreateTexture(nil, "ARTWORK")
        mark:SetSize(62, 62)
        if index == 1 then
            mark:SetPoint("RIGHT", logo, "LEFT", -10, 0)
        else
            mark:SetPoint("LEFT", logo, "RIGHT", 10, 0)
        end
        mark:SetTexture(pack.texture)
    end

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

    -- ── Pack panels ──────────────────────────────────────────────────────
    -- One per pack, built from the table above. Inside the scroll child rather
    -- than pinned to the window, so they sit after the notes instead of
    -- stealing the space the notes need.
    f.promos = {}
    for _, pack in ipairs(PACKS) do
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
        packLogo:SetTexture(pack.texture)

        local packTitle = promo:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        packTitle:SetPoint("TOPLEFT", packLogo, "TOPRIGHT", 12, -2)
        packTitle:SetText(pack.title)
        packTitle:SetTextColor(1, 0.82, 0, 1)

        local packBody = promo:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        packBody:SetPoint("TOPLEFT", packTitle, "BOTTOMLEFT", 0, -6)
        packBody:SetWidth(410)
        packBody:SetJustifyH("LEFT")
        packBody:SetText(pack.body)

        local packBtn = CreateFrame("Button", nil, promo, "UIPanelButtonTemplate")
        packBtn:SetSize(150, 22)
        packBtn:SetPoint("TOPLEFT", packBody, "BOTTOMLEFT", 0, -8)
        packBtn:SetText(pack.button)
        packBtn:SetNormalFontObject("GameFontNormalSmall")
        packBtn:SetScript("OnClick", function()
            StaticPopupDialogs["OXEDHUB_WHATSNEW_PACK_URL"] = {
                text = "Copy the " .. pack.title .. " link (Ctrl+C):",
                button1 = "Done",
                hasEditBox = true,
                OnShow = function(dialog)
                    dialog.EditBox:SetText(pack.url)
                    dialog.EditBox:HighlightText()
                    dialog.EditBox:SetFocus()
                end,
                EditBoxOnEscapePressed = function(dialog) dialog:GetParent():Hide() end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("OXEDHUB_WHATSNEW_PACK_URL")
        end)

        -- Height is set in RenderReleases, once the body text has wrapped and
        -- its real height is known.
        promo.body = packBody
        promo.button = packBtn
        promo.logo = packLogo
        table.insert(f.promos, promo)
    end
    content.promos = f.promos

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

    for _, promo in ipairs(content.promos or {}) do
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
