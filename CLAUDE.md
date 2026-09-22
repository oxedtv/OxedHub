# OxedHub — notes for whoever edits this next

A World of Warcraft addon. Installed copy lives in the retail AddOns folder and
is also the git checkout of `github.com/oxedtv/OxedHub` (branch `main`).

There is no Lua interpreter on the machine this is usually edited from, so
**nothing here is syntax-checked before it ships**. Read carefully, and expect
the player to be the first one to run the code. Errors show up in their Lua
error window, and the line numbers in that report are the fastest way in.

## Ground rules

- Load order is `OxedHub.toc`, top to bottom. A new file does nothing until it
  is listed there. `Core\Loader.lua` must stay first.
- A file that throws while loading takes **every file listed after it** down
  with it. This is why nothing fires events at load time.
- Forward-declare a local before anything references it. Assigning a `local
  function` to a table field above its definition stores `nil`, silently.

## Traps that have already cost time

### Aura data is secret in combat

`C_UnitAuras` reads come back **empty at random** while in combat, even when
the aura is really there. Any code shaped like "it is gone, reset the state"
will flap: one bad read clears the state, the next good read looks like a fresh
aura, and the sound plays again. Several times per cast.

`Modules\Triggers\Bloodlust.lua` handles this by requiring a run of empty reads
(`CLEAR_AFTER_MISSES`) plus a minimum time between announcements
(`MIN_REFIRE`). **Do not "simplify" either of them away.** Copy the pattern for
any new aura trigger that polls.

### Channelled spells fire "cast succeeded" on every tick

`UNIT_SPELLCAST_SUCCEEDED` arrives once **per tick** of a channel — Arcane
Missiles, Penance, Fists of Fury, Mind Flay are four or five events for one
press. A short dedup window does not catch them, because the ticks are further
apart than the window.

`Core\Core.lua` tracks `OxedHub._activeChannel` from
`UNIT_SPELLCAST_CHANNEL_START` / `_STOP` and lets only the first tick through.
The channel start also clears `recentSpellCasts[spellID]` — without that, the
leftover entry from an earlier cast is mistaken for a tick and the spell goes
silent entirely. Both halves are needed.

### A cast rule must never match on "its aura is up"

`Triggers:ShouldTrigger` has a fallback that counts a rule as matched when the
rule's spell is currently an aura on the player. That is right for aura rules
and badly wrong for cast rules: a Spell Cast Success rule for a defensive
(Icebound Fortitude, Anti-Magic Shell) matched on **every** spell cast while
the buff was up, and played its sound each time. The fallback is now skipped
for `SPELL_EVENT_TYPES` and interrupt events, and `ProcessEvent` lets a rule
fire from a cast at most once per `CAST_REFIRE`. Keep both.

### Blizzard template names move between builds

`CreateFrame` with a template that does not exist in this client is an **error**,
not a `nil` return, so it cannot be tested for in advance. Ask for each
candidate inside `pcall` and keep a plain-frame fallback. See `CreateTabButton`
in `Modules\OxedModules\Attributes\Attributes.lua` — the tab template really did
have a different name than expected.

### Key binding names need two globals, not one

`BINDING_HEADER_<HEADER>` names the header, `BINDING_CATEGORY_<CATEGORY>` names
the category. Bindings.xml refers to both; missing either prints the raw key
(`OXEDHUB_CATEGORY`) in the game's panel. Both live at the top level of
`Modules\Toys\ToyDock.lua`, next to the `BINDING_NAME_*` entries — set those at
file scope, never inside a function, or a disabled module leaves its key unnamed.

### The module card clips long descriptions

`ModuleAPI` cards have a fixed height and no ellipsis handling, so `desc` in
`ModuleAPI:Register` must be short — roughly 100 characters — or it is cut off
mid-word. Put anything longer in the options window's `AddNote` instead.

### Chat filters run once per chat window, on possibly secret values

A function added with `ChatFrame_AddMessageEventFilter` is called for **every
chat window** that shows the line, so one message arrives three or four times.
Anything with a side effect — logging, counting repeats — must decide once per
`lineID` and hand every window the same answer (see `decisions` in
`Modules\OxedModules\ChatFilter\ChatFilter.lua`).

On 12.0 the text, the author, the line id and the GUID can each be a **secret
value**. Any string operation or comparison on one errors, so check
`issecretvalue` first and pass the line through untouched. A filter that throws
must return false: breaking chat is worse than letting spam through.

### Show or hide on a secret with SetAlphaFromBoolean, not an if

Whether an enemy cast can be interrupted (`notInterruptible` from
`UnitCastingInfo` / `UnitChannelInfo`) is a secret in combat: Lua cannot read
or compare it. Guessing it from a castbar's shield is wrong whenever no castbar
is visible. Hand the secret to `frame:SetAlphaFromBoolean(secret, 0, alpha)`
and the game hides the frame itself. Two consequences, both seen in KickBar:

- **Nothing on that frame may animate its own alpha.** An Alpha animation on
  the frame drives its alpha while playing and overrides the secret, flashing
  the frame when it should be hidden. Animate child textures instead — their
  alpha multiplies the frame's.
- **Sounds cannot follow the secret.** Playing one is a decision Lua has to
  make, so a sound tied to "interruptible" can only ever use a best guess.

### Anchor list rows with TOPLEFT and TOPRIGHT

`LEFT` and `RIGHT` pin a frame's **vertical centre**. Adding a `TOP` point to a
row that already has them gives it two opinions about where it sits, and rows
drift toward the middle of the list. Clear the points and use `TOPLEFT` +
`TOPRIGHT` with the row's offset.

### Never put a table in a module's DEFAULTS

`ModuleAPI` copies defaults key by key. A table value is copied **by
reference**, so the player's edits are written into `DEFAULTS` itself and every
character shares one list by accident. Create lists in a function after the
settings are bound.

## The profiler (/oxprofile)

`Core\Profiler.lua` loads **second**, right after the loader, and must stay
there. It names OxedHub's work three ways:

- **Methods** wrapped by name at login in `Instrument()` — events, rules,
  triggers, sounds, animations, icons. When adding a new place that does real
  work, add a `WrapMethod` line there rather than timing it by hand.
- **Script handlers**: `SetScript` is hooked on the frame types OxedHub uses, and
  OnUpdate / OnEvent handlers set from an OxedHub file are wrapped with the file
  and line. Protected frames are skipped — never remove that check.
- **Timers**: hot files start with
  `local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer`.
  Never replace the global `C_Timer`: every addon and Blizzard's own code would
  run through OxedHub and get tainted.

**Never create an EditBox without `SetAutoFocus(false)`**, and never one "just to
reach its methods". A new EditBox grabs keyboard focus immediately; an invisible
one locked the player's keyboard — no moving, no casting — until OxedHub was
disabled. The profiler's sample frames are hidden and exclude EditBox for this.

Every wrapper begins with `if not active then return fn(...) end`; keep it
first, so the profiler costs nothing while it is off. A wrapper must return
`fn`'s results unchanged — chat filters and event handlers depend on them.

## Writing a built-in module

`Modules\OxedModules\<Name>\<Name>.lua`, registered via `ModuleAPI:Register`.
Follow the existing ones (`AutoVendor`, `AutoBanker`, `CopyChat`, `Attributes`):

- **Modules ship switched off.** `DEFAULTS.enabled` is `false` in every one;
  players complained about modules acting without being asked. Nothing the
  module does may happen before `OnEnable` — build frames hidden, register
  events in `OnEnable`, and check `settings.enabled` in anything that runs
  earlier. `ModuleAPI:Register` turns off, once, any saved module the player
  never switched themselves (`playerSet` / `defaultOffSeen`) — do not remove it.
- `PLAYER_LOGIN` binds settings, then registers. Never touch `OxedHubDB` earlier.
- Settings live in `OxedHubDB.modules.<id>`; defaults are copied key by key, so
  a key added in a later version reaches players who already have saved data.
- `OnEnable` / `OnDisable` must actually start and stop the work — the module
  card toggles them live, with no reload.
- `category` must be one of the keys in `ModuleAPI.CATEGORIES`; anything else
  silently becomes `general`.
- Options windows come from `API:CreateOptionsWindow`, which offers
  `AddCheckbox` and `AddNote` only.
- Modules in `OxedModules` are written in plain English, not through the
  `Locales` tables. The rest of the addon does use `OxedHub.L`.

## Sending items to the server

Deposits, sales and other per-slot actions must go out **spaced** (see
`AutoBanker`'s `STEP`), not in one burst — a burst is partly dropped and the
dropped items give no error. Re-check each slot's `itemID` immediately before
acting on it: bags shift underneath a run as things stack and sort.

### C_UnitAuras.AddAuraSound is refused for addons

Every call so far has raised ADDON_ACTION_BLOCKED, in or out of combat. It
used to be probed once per OxedHub version + game build, which meant every
release produced a fresh blocked-action error for every player. It is now
treated as refused from the start (`nativeSoundUnavailable = true` in
`Modules\Triggers\SelfAura.lua`); only the Debug page's "Retry aura sound"
button asks the client, and a yes is saved per build. All five PvP trigger
files check `Triggers:IsSelfAuraNativeBlocked()` before calling it. Never add
an automatic probe back.
