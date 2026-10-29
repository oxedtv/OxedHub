# Oxed Hub

## [v2.4.48](https://github.com/oxedtv/OxedHub/tree/v2.4.48) (2026-10-29)
[Full Changelog](https://github.com/oxedtv/OxedHub/compare/v2.4.47...v2.4.48) [Previous Releases](https://github.com/oxedtv/OxedHub/releases)

- Release 2.4.48: Trinket Ready module and MythicLooter This Week tab  
    New Trinket Ready module: sound and a movable alert (size, colour, icon/name) when an on-use trinket is ready.  
    MythicLooter This Week tab: own keystone with teleport, affixes, rating per dungeon, Great Vault progress.  

## [v2.4.47](https://github.com/oxedtv/OxedHub/tree/v2.4.47) (2026-10-28)
[Full Changelog](https://github.com/oxedtv/OxedHub/compare/v2.4.46...v2.4.47) [Previous Releases](https://github.com/oxedtv/OxedHub/releases)

- Release 2.4.47: Interrupt trigger, role marks and Buff Reminder fixes  
    Interrupt rules detect a landed kick again, channels included; Solar Beam, Spell Lock and Axe Toss added.  
    MythicLooter role marks replace a wrong mark and also fire on a ready check in a dungeon.  
    Buff Reminder keeps refreshing inside Mythic+ while auras are hidden.  

## [v2.4.46](https://github.com/oxedtv/OxedHub/tree/v2.4.46) (2026-10-27)
[Full Changelog](https://github.com/oxedtv/OxedHub/compare/v2.4.45...v2.4.46) [Previous Releases](https://github.com/oxedtv/OxedHub/releases)

- Release 2.4.46: OxedHub: prefix on every chat message  
    Every message OxedHub prints to chat now starts with OxedHub:.  

## [v2.4.45](https://github.com/oxedtv/OxedHub/tree/v2.4.45) (2026-10-26)
[Full Changelog](https://github.com/oxedtv/OxedHub/compare/v2.4.44...v2.4.45) [Previous Releases](https://github.com/oxedtv/OxedHub/releases)

- Release 2.4.45: Meme trigger actions, Pet Battle auto-hide, EllesmereUI nameplate anchoring  
    Adds Meme action to Triggers: trigger shake, tilt, or blow up screen effects via OxMemes.  
    Auto-hides OxedHub bars and icons during pet battles, restoring them when battle ends.  
    Buff Reminder: added /oxbuffs why to inspect missing buff display logic.  
    Fixes KickBar and Threat Bar anchoring on EllesmereUI nameplates.  

## [v2.4.44](https://github.com/oxedtv/OxedHub/tree/v2.4.44) (2026-10-25)
[Full Changelog](https://github.com/oxedtv/OxedHub/compare/v2.4.43...v2.4.44) [Previous Releases](https://github.com/oxedtv/OxedHub/releases)

- Release 2.4.44: Russian localization, AddOn Manager, Frame Mover, Toy Keybinds, Buff Reminder & Inviter Info  
    Adds Russian language (testing) support selectable in OxedHub's settings.  
    Adds AddOn Manager module (/oxaddons): organized addon list with plugins grouped, search, character/all toggles, and saved sets.  
    Adds Frame Mover module (/oxmove): drag game windows to save position, Ctrl+wheel to scale, combat protected.  
    Adds Toy mix keybinds (/oxmixkeys) for triggering saved mixes with full audio/visual/chat effects directly.  
    Master toggle on dashboard to disable/restore all modules.  
    Inviter Info: dedicated group join/fill popup with dungeon teleports, test invites, and customizable invite lines.  
    Buff Reminder overhaul: "Choose your buffs" picker, spell suggestions, warlock demon tracking, and contextual filters.  
    Adds standalone minimap buttons for WQ Achievements, Chat Filter, Chat Buttons, Item Tooltips, Cursor, Camera, and Durability.  
    Fixes Run Tracker healer role marks and Shattersight enchanting material shift-hover error.  

## [v2.4.43](https://github.com/oxedtv/OxedHub/tree/v2.4.43) (2026-10-24)
[Full Changelog](https://github.com/oxedtv/OxedHub/compare/v2.4.42...v2.4.43) [Previous Releases](https://github.com/oxedtv/OxedHub/releases)

- Release 2.4.43: Chat Buttons, WQ Achievements, Minimap Buttons, Gold Stock, Chat Filter Last Match  
    Adds Chat Buttons (/oxchat): Say, Group and Guild buttons by the chat window, with whisper  
    history and unread count, mouse-wheel group lines, auto ready check, guild online count,  
    applicant and unread community alerts.  
    Adds WQ Achievements (/wqach): world quests that count toward unfinished achievements or  
    reward uncollected mounts, pets and toys, checked criterion by criterion against the game;  
    achievement screenshots and quest marks on nameplates.  
    Adds Minimap Buttons (/oxmb): every addon's minimap button gathered into one drawer.  
    Adds Gold Stock to Gold World Quests (/gwq gold): gold on every character, guild banks  
    and the warband bank, three views, filter and CSV/JSON export.  
    Chat Filter: Last Match tab with result and rating changes, more PvP players caught,  
    Battle.net report, ignore list as columns with the reason.  
    MythicLooter: group details and a chat reminder in the group joined window.  
    Fixes Bonus Roll Guard and Party Keystones teleports for this season's dungeons.  

## [v2.4.42](https://github.com/oxedtv/OxedHub/tree/v2.4.42) (2026-10-23)
[Full Changelog](https://github.com/oxedtv/OxedHub/compare/v2.4.41...v2.4.42) [Previous Releases](https://github.com/oxedtv/OxedHub/releases)

- Release 2.4.42: Camera module (ActionCam), Currencies, Cursor, and MemedOn optimizations  
    Adds the Camera module (/camera): access the game's ActionCam in a dedicated window,  
    camera tilt (foot and flying), over-the-shoulder view, head movement, target/NPC focus,  
    zoom distance & speed, turn speed, FOV, and presets (Subtle, Cinematic, Action, Off).  
    Optimizes Cursor to sleep when idle (0 updates/sec when mouse rests).  
    Optimizes Currencies to read only changed currencies, eliminating looting stutter & reducing GC.  
    Optimizes MemedOn to track player-only auras instead of all surrounding units.  
    Fixes Currencies tooltip error on hovering the gold line.  

## [v2.4.41](https://github.com/oxedtv/OxedHub/tree/v2.4.41) (2026-10-22)
[Full Changelog](https://github.com/oxedtv/OxedHub/compare/v2.4.20...v2.4.41) [Previous Releases](https://github.com/oxedtv/OxedHub/releases)

- Release 2.4.41: Item Tooltips module and enhancements  
    Adds the new Item Tooltips module (/itt): ID numbers (items, spells, auras, NPCs,  
    currencies, quests, achievements, mounts, toys, pets), aura caster with class/reaction  
    coloring, dispel types & duration, extra item details (ilvl, expansion name & icon,  
    max stack, enchant info, gem sockets, keystone details), account-wide inventory and  
    Warband bank tracking across alts, tooltip preview icon, quality borders, and  
    a comprehensive settings window with 7 categories.  
    Fixes MemedOn spell test trigger audio and optimizes Durability memory usage.  


- Release 2.3.67: three more Modules (Beta) and two repeating-sound fixes  
    Attributes adds a tab to the character window with live movement speed and  
    the stats the sheet leaves out. Auto Banker deposits reagents and restocks  
    whatever you already keep in the bank. Copy Chat opens a chat window as  
    text you can copy, on a key of your choosing. Bloodlust no longer replays  
    itself when the game hides aura data mid-fight, and a channelled spell  
    counts as one cast rather than one per tick.

## [v2.3.66](https://github.com/oxedtv/OxedHub/tree/v2.3.66) (2026-09-11)
[Full Changelog](https://github.com/oxedtv/OxedHub/compare/v2.3.65...v2.3.66) [Previous Releases](https://github.com/oxedtv/OxedHub/releases)

- Release 2.3.66: Modules (Beta) with KickBar, Auto Vendor and Auto Delete  
    Modules become a page of built-in tools, sorted into category tabs and  
    switched on and off from their cards. KickBar moves inside OxedHub and now  
    reads the interrupt cooldown in combat. Adds Auto Vendor (sell junk, repair,  
    guild funds first) and Auto Delete (types the confirmation word). About moves  
    to a ? button beside the close button.  
