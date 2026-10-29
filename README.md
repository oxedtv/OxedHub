# Oxed Hub

A World of Warcraft addon that reacts to what happens in game. You pick an
event — a spell landing, dying, losing control, finishing a Mythic+ — and Oxed
Hub answers with a sound, an animation, an emote, a chat line, or a toy.

Around that sit a few tools that grew out of using it: radial and floating
action bars, a toy organiser, and close to sixty optional modules, from boss
timers and a Mythic+ loot planner to auto-vendoring and a mail helper.

## Install

Drop the `OxedHub` folder into `World of Warcraft/_retail_/Interface/AddOns/`,
or install from [CurseForge](https://www.curseforge.com/projects/1543764),
[Wago](https://addons.wago.io/addons/BNBmAqGx) or
[WoWInterface](https://www.wowinterface.com/downloads/info27142.html).

Type `/oxedhub` (or `/ohub`) to open it.

## What's in it

**Triggers** — the core. Pick an event, pick what happens. Sounds, animations,
emotes, chat messages, toys, or several at once. Every trigger can be limited to
specific zones and given its own keybind.

Around fifty events are covered, grouped into Basic, Combat, PvP and Advanced:
dying, killing a boss, finishing a Mythic+, being interrupted, losing or
regaining control, Bloodlust, a cooldown coming up, gaining or losing an aura, a
specific spell landing, mounting, levelling, earning an achievement, joining a
group, getting mail, and so on. The PvP group covers enemy trinkets, crowd
control on you or your healer, and enemy burst buffs.

**Reactions** — quick emote and sound responses you fire yourself rather than
waiting on an event.

**Toys** — three parts. *Mixer* combines two toys into one button with its own
sound and animation. *My Mixes* keeps what you built. *ToyBoxes* sorts your
collection into boxes with a floating on-screen dock, search, and a random-toy
and random-hearthstone button.

**OxedRing** — a radial menu on a keybind. Slices hold toys, mounts, emotes,
markers, or your own triggers.

**ActionHub** — floating quarter-ring bars for things that do not belong on the
default action bars. Optional dual side, per-node sizing, an alignment grid
while positioning, and cooldown sweeps with charge counts.

## Modules

The Modules page holds self-contained features you switch on one by one. Every
module ships **switched off**: nothing happens until you turn it on, and
turning it off stops it at once, with no reload. Each card has an Options
button, and the page can be searched and filtered by category.

### Combat

- **Buff Reminder** — icons for missing raid buffs, pets and consumables; click one to cast it. Keeps working in Mythic+.
- **Buff Tracker** — any buff on you as a big icon with a timer, also in a fight.
- **BRes & Lust Tracker** — battle resurrection charges and Sated on screen.
- **Heartbeat** — a heartbeat in combat that speeds up at low health, and a flatline when you die.
- **KickBar** — an interrupt alert on the enemy's nameplate or a floating icon, with a timer and an almost-ready preview.
- **Markers** — raid marks, world flares, a ready check and a pull timer on screen (`/oxmark`).
- **Smart Misdirect** — Misdirection and Tricks of the Trade on the right target with one button.
- **Threat Bar** — a threat bar under every enemy nameplate, glowing as you close in (`/oxthreat`).
- **Trinket Ready** — a sound and a movable alert the moment an on-use trinket is ready again.

### Dungeons & PvP

- **MythicLooter** — Mythic+ and raid loot browser with a Best-in-Slot planner, drop reminders, keystone tooltips, the party's keys, and a This Week tab with your key, affixes, rating and Great Vault progress. During a key, a forces tracker with boss targets (`/ml`).
- **Boss Timers**, **Boss Alerts**, **Boss Track**, **Boss Health** — boss abilities as bars, centre-screen countdowns, icons sliding toward a line, and a health bar with phase marks. Each ability can have its own sound and text.
- **Trash Timers** — cooldowns of dangerous dungeon trash after each pull.
- **Enemy Casts** — every enemy cast in one list, with its target; greyed when it cannot be kicked.
- **Party Interrupts** — your kick's cooldown, and who in the group just interrupted what.
- **Auto Queue** — answers role checks, signs up in the Group Finder, and a movable queue eye.
- **Inviter Info** — who is inviting you, and the group's details when the Group Finder puts you in one.
- **Bonus Roll Guard** — asks before a bonus roll is spent, and names the spec the loot goes to.
- **Loot Banner** — trims the boss loot banner: nothing when solo, only good items, or only yours.
- **Instances** — instances per hour, and what each run was worth (`/oxinst`).
- **PvP Progress** — honour, conquest, vault wins and every rating on one panel (`/oxpvp`).

### Quests & Travel

- **Teleports** — one button your teleports fly out of, each group its own way (`/tp`).
- **Auto Quest** and **Auto Gossip** — accept and hand in quests, and pick the only option in an NPC's menu.
- **Flight Timer** — a timer bar on flight paths, with a sound before you land (`/oxflight`).
- **Gold World Quests** — gold world quests, special assignments and weekly caches in Midnight.
- **WQ Achievements** — world quests up now that count toward achievements, mounts, pets or toys you still need.
- **Prey Hunt** — the hunt's stages as a bar, ambush and kill sounds, and achievement marks at Astalor.
- **Quest Item Alert** — names the quest an item starts before you delete it, and whether you did it.

### Bags & Mail

- **Auto Vendor** — sells junk and your sell list, and repairs, at any vendor.
- **Auto Banker** — deposits reagents and restocks what you keep in the bank.
- **Auto Confirm** — types DELETE for you and skips the confirm popups you choose.
- **Bulk Buy** — Shift-click a vendor item to buy any amount, with the total cost.
- **Purchase Guard** — holds the Yes button a moment on purchases you cannot undo.
- **Fast Loot** — takes all the loot the moment the window opens.
- **Durability** — gear durability on screen, the worst slots, repair cost, and a reminder before a dungeon.
- **Item Tooltips** — IDs, collection status and counts across your characters in tooltips.
- **Mail** — Open All, return, forward, an address book and attaching from bags (`/oxmail`).

### Character & UI

- **Attributes** — a character window tab with live movement speed and hidden stats such as leech and stagger.
- **Currencies** and **Reputations** — every currency and renown for all your characters, with totals and paragon alerts (`/oxcurrency`, `/oxrep`).
- **Currency Transfer** — quicker account-wide currency transfers.
- **Experience Bar** — an experience bar with quest XP, rested bonus and levelling rate (`/oxexp`).
- **AddOn Manager** — addons grouped and searchable, switched per character, with saved sets (`/oxaddons`).
- **Frame Mover** — drag the game's windows anywhere, and they open there again (`/oxmove`).
- **Minimap Buttons** — every addon's minimap button in one drawer.
- **Missing Gems** — marks gear with empty sockets and reminds you before a dungeon.
- **Camera** — ActionCam settings in a window: tilt, over the shoulder, target focus, field of view.
- **Cursor** — fire, frost and other effects on your mouse pointer.
- **Break Time** — a friendly reminder to stand up after a long session, never in a fight.

### Chat

- **Chat Filter** — an unlimited ignore list, Group Finder warnings and spam blocking (`/oxfilter`).
- **Chat Buttons** — Say, Group and Guild buttons by the chat, with whisper history and quick lines.
- **BubbleChat** — chat bubbles in your font, size and style (`/oxbubble`).
- **Copy Chat** — opens the chat as text you can copy (bind it under Key Bindings, Oxed Hub).
- **Chat Leave** — right-click a channel in chat to leave it.
- **OxMemes** — keywords in chat, NPC lines and spells shake, tilt or blow up the screen with a sound.

## Sharing

Anything you build can be handed to another player through chat: a single
trigger, a ring, a toy mix, an action hub, or a whole profile.

The link carries only a short code. When someone clicks it, the two addons talk
directly and transfer the data between them, so nothing is limited by chat's
255-character cap. Both players have to stay online until it finishes; a large
profile takes around half a minute.

Before anything is applied you see exactly what is inside — including which
triggers would speak in chat or use emotes on your behalf, and which toys you
already own. Nothing is ever imported silently.

## Profiles

Separate setups per character or per spec, with automatic switching by class.
Everything can also be exported as a text string if you would rather move it by
hand.

## Slash commands

| Command | Does |
| --- | --- |
| `/oxedhub`, `/ohub`, `/oxed` | Open the main window |
| `/oxedring` | Toggle the radial menu |
| `/oxprofile` | Record what OxedHub costs per frame, and what caused a hitch |

Modules add their own commands, shown next to each one above.

Key bindings for the ToyBox panel, random toy and random hearthstone, Copy Chat
and other modules live in the game's own Key Bindings panel, under **Oxed Hub**.

## Languages

English, Spanish, Arabic and Russian (the Russian is still being tested). The
language is picked in OxedHub's settings, not taken from the game client.
Translations are welcome — the strings all live in `Locales/`, one file per
language.

## Reporting a problem

Open an issue with your addon version (shown at the bottom-left of the main
window), what you were doing, and the error text if there was one. Errors are
much easier to act on with [BugSack](https://www.curseforge.com/wow/addons/bugsack)
installed, since it keeps the full stack trace.

## Building a release

Releases are automated. `scripts/set-version.sh` writes a version into every
file that carries one, and the **Bump version and release** workflow on GitHub
does the rest: tag, package, and upload to CurseForge, Wago and WoWInterface.

Every push is checked first — Lua syntax, that every file listed in the `.toc`
exists, and that the version agrees across files.

## Licence

All rights reserved. Please ask before redistributing or reusing the code.
