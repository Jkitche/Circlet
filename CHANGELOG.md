# Changelog

## Unreleased

- **Food & Drink ring** (new; on by default). While you eat or drink, the ring fills with your
  health or mana (whichever is further from full when you do both), counts down the buff and
  bursts when you're full. Eating throws crumbs off the ring with every bite; drinking sends
  bubbles up through it and a ripple out with every gulp (Food & Drink > Animations). Preview
  with `/circ food`.
- **Removed: follow what you're interacting with.** The cast ring no longer moves onto the
  chest or quest object you're using (it didn't work reliably), and `/circ follow` is gone. Interaction
  casts still get the finish burst.

## 1.0.0

- **Ammo ring: Always show** (off by default; Ammo > Always show). The ring shows every time you
  shoot and counts down what's left, instead of only at the warning steps. Nothing shows while the
  game keeps the count hidden; the next readable count carries on from the last one.
- **Ammo ring: Keep up in combat** (off by default; Ammo > Keep up in combat). When a fight
  starts the ring comes up with what you have, counts down every shot and stays until the fight
  is over, then fades after its hold time. Overrides Wait until combat ends; needs Show in combat.
- **Ammo ring: flash when low** (Ammo > Flash at or below, default 15%). The ring flashes once
  what's left is at or below that share of a full supply (the most carried since the last restock),
  with Always show or with the warnings. 0 turns it off.
- The ammo options now say plainly that, without Always show, the ring shows every quarter of the
  warning level rather than on every shot.
- **Fill backwards** (every ring, in its Appearance box): the ring fills counter-clockwise from
  the other end. The gradient and segments follow the fill; "Apply this look to all rings" copies it.
- **`/sq` is gone**: use `/circ` (or `/circlet`) for the options and every command.
- **Cast ring: spell school effects** (on by default; Casting > Spell school effects). While you
  cast, the ring glows in the school's color with an aura round its band and particles that spill
  out past it: embers rising for fire, snowflakes drifting down for frost, motes orbiting for
  arcane, wisps spiraling into a dark core for shadow, an outward swirl for nature and turning
  rays for holy. Effect strength (25-200%) sets how bold it is. The school comes from a built-in list of
  class spells (any rank) or the icon. Physical and unknown spells have none. Edit mode's sample
  goes round every school.
- **Cast ring: resurrection animation.** Casting a resurrect (Resurrection, Redemption,
  Ancestral Spirit, Rebirth and the rest, any rank) fills the ring in a soft holy gold with
  motes of light rising through it. When it goes off a pillar of light shoots up, the ring
  flashes and a wave rolls out; if it's interrupted the light gutters out. On by default
  (Casting > Resurrection animation), with its own color. Shown in the cast ring's preview.
- **Icon as background** for every ring with an icon (cast, gathering, crafting, ammo, pet,
  reputation, profession and weapon skill): the icon fills the middle of the ring behind its
  text instead of sitting on the top edge, with its own opacity setting. Off by default; in
  each ring's General options.
- **Finish burst**: when a gather brings something in (or a fish is caught), a crafting batch
  finishes or an interaction cast (opening a chest, using a quest object) goes off, the ring's
  icon swells, flashes and throws off a ring of sparks, at a random angle each time with a little
  variety in each spark. Spells don't burst. A dimmed background icon turns fully opaque when
  anything finishes, spells included. The crafting preview now shows the finishing batch first,
  so `/circ craft` shows it.

## 0.62.0

First public release.

- **Rings**: XP (rested band, level-up effects, optional always-on, hide text when idle, or as
  a ring around the minimap), quest objectives (with a turn-in alert), professions, weapon
  skills, reputation, pet XP (hunters), ammo and soul shards, flight paths (route times are
  learned as you fly), timed quests, corpse runs (distance and an arrow toward your corpse),
  breath / fatigue / Feign Death, crafting batches, gathering (shows what you got), casts
  (timed even in combat) and totems (shamans). Pin any quest from the quest log to give it
  its own ring.
- **Look**: per ring style (smooth, segmented, thin), shape (ring, arc, half arc), rotation,
  solid or gradient fill, black border, opacity, size and colors. Apply one ring's look to all.
- **Placement**: edit mode with live previews, drag to move with a snap grid, auto-arrange so
  rings that pop up together don't overlap.
- **Options**: hide each ring in combat, hide the game's own bar a ring replaces (XP bar, cast
  bar, breath bar...), per-character profiles.
- **Effects**: welcome animation on login, a "discovered" animation for new areas, and a
  session summary.
