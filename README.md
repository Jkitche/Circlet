# Circlet

Progress rings for World of Warcraft (WoW Forever). Rings pop up and fill as things happen,
then fade away, or stay up as a permanent display.

## Rings

- **XP**: XP and rested XP, level-ups, rested XP gained at inns (with the resting zZZ). Can
  stay up permanently, hide its text when idle, or wrap around the minimap.
- **Quest**: objective progress, with a turn-in alert. **Quest rings**: pin a quest from the
  quest log to keep its own ring on screen.
- **Professions** and **Weapon skills**: skill-ups and new training tiers.
- **Reputation**: gains, losses and new standings.
- **Pet** (hunters) and **Ammo** (arrows, bullets, thrown, soul shards).
- **Flight**: time left on a flight path (learned per route). **Timed quest**: quest timers.
- **Corpse**: distance and direction to your corpse. **Breath**: breath, fatigue and Feign Death.
- **Crafting** (batches), **Gathering** (with what you got) and **Cast** (timed even in combat).
- **Totems** (shamans): one small ring per element.

Each ring has its own colors, style (smooth, segmented, thin), shape (ring, arc, half arc),
rotation, solid or gradient fill, border, opacity, size and position, and can hide in combat
or hide the game's own bar it replaces. Profiles keep separate setups per character.

## Install

Install from CurseForge, or copy the `Circlet` folder from a release zip to
`World of Warcraft\_forever_\Interface\AddOns\`.

## Use

- `/sq` (or `/circlet`, `/circ`) opens the options.
- `/sq help` lists the commands: previews for every ring (`/sq xp`, `/sq cast`, ...),
  `/sq edit <ring>` to see a ring live and drag it, `/sq profile [name]`, and more.

## Code layout

Files load in `Circlet.toc` order and share everything through the addon's `ns` table.

- `Core/`: helpers (`Init.lua`), saved settings and the `db` table (`Settings.lua`), the ring
  registry (`Registry.lua`), the `/sq` command (`Slash.lua`) and startup (`Events.lua`).
- `Draw/`: drawing rings (segments, arcs, track, border, styles, shapes, gradients) and glyphs.
- `Layout/`: each ring's holder frame (opacity, hiding in combat), auto-arrange, dragging.
- `Rings/Base/`: what every ring frame shares (`RingFrame.lua`) and the two ring builders:
  `ProgressRing.lua` (pops up when something changes) and `LiveRing.lua` (shows a live state).
- `Rings/`: one file per ring. Each ends with `ns.RegisterRing{...}`: its defaults, edit mode
  hooks, preview and slash names, options page, class filter and the game bar it can hide.
  Edit mode, `/sq` and its help, the options window and the defaults are built from these, so
  a new ring is one new file (plus its line in the TOC).
- `Features/`: edit mode, profiles, one-time settings migrations, hiding the game's bars, the
  welcome and discovery animations, the session summary.
- `UI/`: option builders (`OptionsKit.lua`), the options window, the icon list.

## Tests

`python3 tests/run_tests.py` runs every test against a mock of the game's API and compares the
output with `tests/golden/` (needs Python 3 and `pip install lupa`). After an intended change,
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
