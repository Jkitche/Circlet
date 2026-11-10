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
- **Ammo and soul shards**: shows when you're at or below a warning amount.
- **Totems** (shamans): one small ring per element, pulsing in the last 10 seconds. Durations are
  learned, so they keep counting in combat.

**Travel and timers**
- **Flight paths**: a countdown to landing. Route times are learned the first time you fly them.
- **Timed quests**: escort and other quest timers, changing color near the end.

**Death and breath**
- **Corpse run**: distance to your body, an arrow pointing to it, and when you can resurrect.
- **Breath, fatigue and Feign Death**, with rising bubbles while you hold your breath.

**Crafting, gathering and casting**
- **Crafting**: progress through a batch (single crafts optional), with the item's icon.
- **Gathering**: mining, herbalism, skinning and fishing, then what you got.
- **Casts**: casts and channels, timed even in combat. Spell school effects (fire, frost, arcane,
  shadow, nature, holy) with a strength setting, and a resurrection animation.
- **Finish burst**: when a gather, craft or interaction finishes, the icon swells and throws
  off sparks.
- **Follow the target**: the cast ring can sit on the chest or quest object you're opening or
  using and move with the camera.

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

- `/circ edit [ring]`: see a ring live and drag it into place.
- Ring previews: `/circ xp`, `quest`, `pins`, `skill`, `weapon`, `rep`, `pet`, `ammo`, `flight`,
  `timed`, `corpse`, `breath`, `craft`, `gather`, `cast`, `totems`.
- Effect previews: `/circ levelup`, `rested`, `complete`, `hello`, `discover`.
- `/circ summary`: this session's summary.
- `/circ profile [name]`: list or switch profiles.
- `/circ ring <quest>` / `/circ ring clear`: pin or clear quest rings.
- `/circ follow`, `/circ icons`: check the follow-the-target setup and the icons the rings use.

## Code layout

Files load in `Circlet.toc` order and share everything through the addon's `ns` table.

- `Core/`: helpers (`Init.lua`), saved settings and the `db` table (`Settings.lua`), the ring
  registry (`Registry.lua`), the `/circ` command (`Slash.lua`) and startup (`Events.lua`).
- `Draw/`: drawing rings (segments, arcs, track, border, styles, shapes, gradients) and glyphs.
- `Layout/`: each ring's holder frame (opacity, hiding in combat), auto-arrange, dragging,
  following the interact target (`Follow.lua`).
- `Rings/Base/`: what every ring frame shares (`RingFrame.lua`) and the two ring builders:
  `ProgressRing.lua` (pops up when something changes) and `LiveRing.lua` (shows a live state).
- `Rings/`: one file per ring. Each ends with `ns.RegisterRing{...}`: its defaults, edit mode
  hooks, preview and slash names, options page, class filter and the game bar it can hide.
  Edit mode, `/circ` and its help, the options window and the defaults are built from these, so
  a new ring is one new file (plus its line in the TOC).
- `Features/`: edit mode, profiles, one-time settings migrations, hiding the game's bars, the
  welcome and discovery animations, the session summary.
- `UI/`: option builders (`OptionsKit.lua`), the options window, the icon list.

## Tests

`python3 tests/run_tests.py` runs every test against a mock of the game's API and compares the
output with `tests/golden/` (needs Python 3 and `pip install lupa pillow`). After an intended change,
`python3 tests/run_tests.py --update <test>` accepts the new output; check the diff first.

## Releasing

Releases go to CurseForge from GitHub: bump the version in `CHANGELOG.md` (newest at the top),
commit, then tag and push it:

    git tag v0.62.1 && git push origin v0.62.1

`.github/workflows/release.yml` runs the tests and the BigWigs packager, which builds the zip
(see `.pkgmeta`), puts the changelog on the file and uploads it to CurseForge and as a GitHub
release. It needs the project's ID in `Circlet.toc` (`## X-Curse-Project-ID`) and a
CurseForge API token as the `CF_API_KEY` repository secret. `python3 tools/package.py` builds
the same zip locally (into `dist/`) for a manual upload or a test install. The CurseForge page
text is in `docs/curseforge.md`.

## Libraries

Embeds LibStub, CallbackHandler-1.0, AceGUI-3.0 and AceConfig-3.0 (see their LICENSE files in
`Libs`). Circlet doesn't depend on any other addon.
