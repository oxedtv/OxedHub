# Oxed Hub

A World of Warcraft addon that reacts to what happens in game. You pick an
event — a spell landing, dying, losing control, finishing a Mythic+ — and Oxed
Hub answers with a sound, an animation, an emote, a chat line, or a toy.

Around that sit a few tools that grew out of using it: radial and floating
action bars, a toy organiser, and two trackers.

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
group, getting mail, and so on. A few are small trackers in their own right — a
battleground idle timer that warns you before the game kicks you, and a Prey
hunt tracker with stage progress and achievement markers on Astalor's gossip
list.

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

Key bindings for the ToyBox panel, random toy and random hearthstone live in the
game's own Key Bindings panel, under **Oxed Hub**.

## Languages

English, Spanish and Arabic. Translations are welcome — the strings all live in
`Locales/`, one file per language.

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
