# Circlet

Progress rings for World of Warcraft (WoW Forever). Rings pop up and fill as things happen,
then fade away, or stay up as a permanent display.

## Rings

**XP**
- Fills with each gain and shows how much it was ("+23.6%"). Colored by rest state, with the
  rested band ahead of the fill.
- Level-up effect: gold, rainbow or none.
- At an inn or city, stays up while rested XP builds, with an animated zZZ. When you leave,
  shows how much rested XP you gained there.
- Can stay on screen as your XP bar (its text fades after a few idle seconds), or wrap around
  the minimap, with an adjustable gap and the option to sit behind the minimap's border.

**Quests**
- Objective progress ("Screecher Feather 5 / 8"), a "!" animation when an objective completes,
  and a "Ready to turn in" alert once every objective is done.
- **Quest rings**: right-click a quest in the quest log (or `/circ ring <name>`) to give it its
  own ring, with one notch per objective. They stack by the quest tracker, can be dragged, and
  are removed from their right-click menu.

**Skills and reputation**
- **Professions**: profession and secondary skill-ups, new training tiers and "capped", with the
  game's icons or line-drawn ones.
- **Weapon skills**: weapon skills and Defense, on their own ring.
- **Reputation**: gains, losses and new standings, with the faction's icon.

**Class and inventory**
- **Pet XP** (hunters), with your pet's portrait.
- **Ammo and soul shards**: shows when you're at or below a warning amount, or on every shot
  with Always show, or kept up for the whole fight; flashes when you're nearly out.
- **Totems** (shamans): one small ring per element, pulsing in the last 10 seconds. Durations are
  learned, so they keep counting in combat.

**Travel and timers**
- **Flight paths**: a countdown to landing, timed from the game's own flight path data (mined
  from the WoW Forever client), so every route counts down from the first flight.
- **Timed quests**: escort and other quest timers, changing color near the end.

**Food and drink**
- **Eating and drinking**: the food or drink buff filling the ring and counting down, bursting
  when it's done. While eating, steam rises and each chomp bites the ring,
  crumbs flying; while drinking, water fills the ring and sloshes with every gulp. Doing both
  splits the ring: eating up the left side, drinking up the right.

**Camping**
- **Campfire**: resting at a camp (Welcoming Campfire) counting down to Well Rested, with
  firelight and embers rising through the ring.

**Clock and timer**
- **Clock** (off until you turn it on): a ring that fills through the hour with a dot at the
  hour and ticks around it, showing the time, day and date. Local or realm time, 12 or 24 hours.
  The dot becomes a rising sun in the morning, a setting sun in the evening and a moon at night.
- **Timer**: a countdown you start yourself with `/circ timer 5m Tea` (or `1:30`, `90`, `1h20m`,
  `10 min Pull`; `+2m` adds time, `stop` stops it). It drains with a pocket watch icon, pulses near
  the end, then bursts with a sound and the label on screen. It keeps going through a reload.

**Groups**
- **Loot rolls**: the time left to roll Need or Greed, with a dice badge and the item's name in
  its quality color; shows your pick once you've rolled, and warns in the last few seconds.
- **Ready checks**: the time left to answer, who started it and how many are ready, with the
  game's ready check icon; red as soon as anyone isn't ready, then the result ("All ready!").

**Death and breath**
- **Corpse run**: distance to your body, an arrow pointing to it, and when you can resurrect,
  with a revive animation when you're back in your body.
- **Breath, fatigue and Feign Death**, with rising bubbles while you hold your breath.

**Crafting, gathering and casting**
- **Crafting**: progress through a batch (single crafts optional), with the item's icon.
- **Gathering**: mining, herbalism and skinning, then what you got. Each profession gets an
  animation of its own at the ring's top right: a knife slashes along the ring for skinning, flicking off tufts of fur;
  a pickaxe strikes the ring's edge for mining, in sparks and chips of rock; pruning shears
  snip at it for herbalism, leaves and petals fluttering off.
- **Fishing**: counts down the cast with the fill bobbing like a float, flashes in the usual
  bite windows, then shows the catch. Optionally, right-click anywhere to reel in (out of combat only).
- **Casts**: casts and channels, timed even in combat. Spell school effects (fire, frost, arcane,
  shadow, nature, holy) with a strength setting, and a resurrection animation.
- **Mana regen**: the five-second rule after you spend mana, counting down to when your mana
  regen starts again.
- **Weapon imbue** (shamans): time left on Rockbiter, Flametongue, Frostbrand or Windfury, each
  with its own animation.
- **Soulstone** (warlocks): who has your soulstone and how long it has left, and a reminder
  when none is out.
- **Swing timer**: time to your next melee swing while you auto-attack, and how the last one
  went (hit, crit, glancing, dodged, parried...).
- **Shot timer**: time to your next Auto Shot, wand shot or throw, with Auto Shot's aim (hold
  still!) marked.
- **Health & power**: your health and power, your target's and its target's, with combo points,
  raid markers, an aggro warning, execute range, a low-health heartbeat, energy ticks, damage
  and healing numbers, and the elite dragon.
- **Target casts**: what your target is casting or channeling, who's casting it, and whether
  you can interrupt it; red with the lost part flashing when it's interrupted.
- **Finish burst**: when a gather, craft or interaction finishes, the icon swells and throws
  off sparks.

## Look

Per ring:

- Style (smooth, segmented, thin) and shape (full ring, three-quarter arc, half arc).
- Rotation in degrees, and filling clockwise or counter-clockwise.
- Solid or gradient fill, with adjustable gradient strength.
- Black border width, size, thickness, opacity and colors.
- The icon as a badge on the ring's edge, or filling its middle at a chosen opacity.
- Apply one ring's look to all the others.

## Placement and behavior

- **Edit mode**: each ring shows live with sample content while you change its settings; drag it
  into place, with an adjustable snap grid.
- **Auto-arrange**: rings that pop up together slide apart instead of overlapping, then slide back.
- Hide any ring in combat, or hold some gains until combat ends. Set how long each ring stays up.
- Hide the game's own bar a ring replaces: the XP bar, reputation bar, cast bar (while crafting or
  gathering), breath and fatigue bars, quest timer and totem timers.
- Turn any ring on or off.

## Extras

- **Setup wizard** the first time Circlet runs: pick your rings (each with a Show button to see it),
  hide the game bars they replace, choose one look for every ring, and set the layout. After an
  update, players who had Circlet before get a **"New in" page** with just what's new, each with
  an on/off box and Show. `/circ setup` and `/circ new` bring them back.
- **Welcome animation** on login: rings spin open, your name types out in your class color,
  then your level, zone, how rested you are and when you last played.
- **"Discovered" animation** when you explore a new area.
- **Session summary**: XP, levels, quests, skills, reputation, flights, pet XP, deaths and money
  for this session, optionally shown when you log out.
- **Profiles** per character. Learned data (flight times, totem durations, cast times) is shared
  by all characters.
- An addon compartment button that opens the options.
- No other addons needed: the libraries it uses are built in.

## Install

Install from CurseForge, or copy the `Circlet` folder from a release zip to
`World of Warcraft\_forever_\Interface\AddOns\`.

## Commands

`/circ` (or `/circlet`) opens the options. `/circ help` lists everything.

- `/circ setup`: the setup wizard. `/circ new`: what's new in this version.
- `/circ timer <time> [label]`: start a countdown ring (`/circ timer +2m` adds time, `stop` ends it).
- `/circ edit [ring]`: see a ring live and drag it into place.
- Ring previews: `/circ xp`, `quest`, `pins`, `skill`, `weapon`, `rep`, `pet`, `ammo`, `flight`,
  `timed`, `corpse`, `breath`, `food`, `camp`, `clock`, `craft`, `gather`, `fish`, `cast`, `regen`, `totems`.
- Effect previews: `/circ levelup`, `rested`, `complete`, `hello`, `discover`.
- `/circ summary`: this session's summary.
- `/circ profile [name]`: list or switch profiles.
- `/circ ring <quest>` / `/circ ring clear`: pin or clear quest rings.
- `/circ icons`: list the game icons the rings use.

## Local development

Clone the repo into the game's `Interface` folder, next to `AddOns` (not inside it):

```
cd "D:\World of Warcraft\_forever_\Interface"
git clone https://github.com/Jkitche/Circlet.git
```

After each change, copy the addon into `AddOns\Circlet`:

```
localDeploy.cmd           (or .\localDeploy.ps1, or ./localDeploy.sh in Git Bash)
```

Then `/reload` in game, or restart the game if a file was added or removed. The script
copies only what a release would contain (everything except what `.pkgmeta` ignores) and
mirrors the folder, so files deleted from the repo are removed from `AddOns\Circlet` too.
`-WhatIf` (PowerShell) or `DRY_RUN=1` (bash) shows what it would do without changing
anything.

## Code layout

Files load in `Circlet.toc` order and share everything through the addon's `ns` table.

- `Core/`: helpers (`Init.lua`), saved settings and the `db` table (`Settings.lua`), the ring
  registry (`Registry.lua`), the `/circ` command (`Slash.lua`) and startup (`Events.lua`).
- `Draw/`: drawing rings (segments, arcs, track, border, styles, shapes, gradients) and glyphs.
- `Rings/Base/`: what every ring frame shares (`RingFrame.lua`) and the two ring builders:
  `ProgressRing.lua` (pops up when something changes) and `LiveRing.lua` (shows a live state).
- `Rings/<Folder>/`: the rings, in the same folders as the options window's list: `Progress`,
  `Health`, `Combat`, `Class/<Class>`, `Group`, `Travel`, `Professions`, `Comfort`. Each ring
  ends with `ns.RegisterRing{...}`: its defaults, edit mode hooks, preview and slash names,
  options page (`page.folder` picks its folder in the window), class filter and the game bar it
  can hide. A big ring is a folder of its own, split by concern and ending in `Register.lua`:
  `Progress/XP/`, `Progress/Skills/`, `Combat/TargetCast/`, and `Health/` (the health rings,
  with their effects in `Health/Fx/`). A new ring gets
  `since = "x.y.z"` (its release) so players updating see it on the "New in" page;
  `Features/Setup/` also lists its group in the setup wizard (`GROUPS`) and new features that
  aren't rings (`NEW_FEATURES`).
  Edit mode, `/circ` and its help, the options window and the defaults are built from these, so
  a new ring is one new file (plus its line in the TOC). A ring for one class goes in
  `Rings/Class/<Class>/` with `class = { <CLASS> = true }` and `page.folder = "class"`.
- `Features/`: profiles, one-time settings migrations, hiding the game's bars, the welcome and
  discovery animations, the session summary, and the setup wizard (`Setup/`).
- `UI/`: widgets, the window skin, the icon list, and the options window (`Options/`: the option
  builders in `Kit.lua`, then the pages, the window and its sidebar).
- `Layout/`: each ring's holder frame, auto-arrange, dragging and edit mode.

A folder split from one file shares what its files need through a private table on `ns`, made
by its first file (`ns.OptionsUI`, `ns.HealthRings`, `ns.HealthFx`, `ns.XPRing`, `ns.SkillRings`,
`ns.TargetCastRing`, `ns.SetupUI`, `ns.CraftFx`). Each file takes what it uses from the table
once, at its top (`local Eval = UI.Eval`); a value that's reassigned after loading (the window,
the current page, a timer) is always used through the table (`UI.current`), never copied into
a local, or the copy would go stale.

## Tests

`python3 tests/run_tests.py` runs every test against a mock of the game's API and compares the
output with `tests/golden/` (needs Python 3 and `pip install lupa pillow`). After an intended change,
`python3 tests/run_tests.py --update <test>` accepts the new output; check the diff first.

## Releasing

Releases go to CurseForge from GitHub: bump the version in `CHANGELOG.md` (newest at the top),
commit, then tag and push it:

    git tag v1.1.1 && git push origin v1.1.1

`.github/workflows/release.yml` runs the tests and the BigWigs packager, which builds the zip
(see `.pkgmeta`), puts the changelog on the file and uploads it to CurseForge and as a GitHub
release. It needs the project's ID in `Circlet.toc` (`## X-Curse-Project-ID`) and a
CurseForge API token as the `CF_API_KEY` repository secret. `python3 tools/package.py` builds
the same zip locally (into `dist/`) for a manual upload or a test install. The CurseForge page
text is in `docs/curseforge.md`.

## Libraries

Embeds LibStub, CallbackHandler-1.0, AceGUI-3.0 and AceConfig-3.0 (see their LICENSE files in
`Libs`). Circlet doesn't depend on any other addon.
