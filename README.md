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

Copy this folder to `World of Warcraft\_forever_\Interface\AddOns\Circlet`.

## Use

- `/sq` (or `/circlet`, `/circ`) opens the options.
- `/sq help` lists the commands: previews for every ring (`/sq xp`, `/sq cast`, ...),
  `/sq edit <ring>` to see a ring live and drag it, `/sq profile [name]`, and more.

## Libraries

Embeds LibStub, CallbackHandler-1.0, AceGUI-3.0 and AceConfig-3.0 (see their LICENSE files in
`Libs`). Circlet doesn't depend on any other addon.
