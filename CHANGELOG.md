# Changelog

## 1.2.0

- **Circlet's windows get a look of their own.** The setup wizard, the New in page and the session
  summary now have a deep gradient background with a soft shadow, a thin gold border, a header band
  with a turning Circlet logo and a gold accent line, and open with a quick fade. In the wizard a
  step ring fills one notch per step, sections have gold underlines, rows light up under the
  mouse, the Look choices are picture cards showing mini rings in each style and size, and each
  new thing on the New in page sits on its own panel with a NEW tag.
- **Setup wizard** (new). The first time Circlet runs, a short wizard opens a few seconds after the
  welcome animation: pick your rings by group (each with a Show button that puts it on screen with
  sample content), hide the game bars they replace, choose one style and size for every ring (or keep
  each ring's own), and keep, reset or arrange the layout. Skip it any time. `/circ setup` or
  General > Setup wizard brings it back.
- **"New in" page** (new). After an update, players who had Circlet before see what's been added
  since, just once: each new ring or feature with an on/off box and Show. This release lists the
  target cast, loot roll, ready check and clock rings and the corpse revive animation. `/circ new` or
  General > What's new shows it again.
- **Rings stay under the game's windows.** The rings and their effects (the discovery flourish,
  the welcome, level-up and quest-complete animations) now sit below the game's own windows (bags,
  character sheet, map, spellbook...) instead of on top of them. Around the minimap the XP ring still
  draws over the map (or under it, with its Behind the minimap option). In edit mode rings still come
  to the front, so you can drag them over the options window.
- **Ready check ring** (new; on by default). While a ready check runs, the ring drains over the
  time left to answer, with who started it, the seconds left and how many are ready ("3/5 ready"),
  and the game's ready check icon as a badge (or filling the ring's middle: Ready checks > Icon as
  background). It asks "Are you ready?" until you answer and turns red as soon as anyone isn't
  ready. When the check ends it shows the result for a moment: "All ready!", or how many weren't
  ready and how many never answered. Preview with `/circ ready`.
- **Loot roll ring** (new; on by default). While an item is being rolled for, the ring drains over
  the time left to roll, with the Need roll's dice as a badge (or filling the ring's middle: Loot
  rolls > Icon as background), the item's name in its quality color and the seconds
  left, turning red in the last 10 seconds (Loot rolls > Warn at). Once you roll it shows your pick
  ("Rolled Need"); pass and that roll drops off. With several rolls at once, the ones you still have
  to answer come first. Stays up in combat. Preview with `/circ loot`.
- **Clock ring** (new; off until you turn it on: Clock > Show clock ring). A clock that stays on
  screen: the ring fills as the hour goes by, a dot rides it at the hour, ticks mark the hours,
  and the middle shows the time with the day and date. Your computer's time or the realm's, 12 or
  24 hours. The hour dot becomes a rising sun in the morning, a setting sun in the evening and a
  crescent moon at night (Clock > Sun and moon). Preview with `/circ clock`.
- **Fixed: totem rings could get stuck after combat** as a bare ring with no icon or timer. A slot
  the game reports as empty now clears even while it hides the totem's times, and the game's own
  countdown (used for totems not yet learned) gives up once even your longest totem would be over.
- **Fixed: totem rings showing in combat with no totem down, or staying after a totem died.** When
  the game hides totem times and Circlet can't be sure a totem is there (one it hasn't learned, a
  spell cast just as a totem expired, or a totem killed while the game hides which slot changed),
  the ring now shows only the game's own icon and timer, with no ring of its own, so an empty slot
  shows nothing. A totem killed mid-fight no longer leaves its countdown running.

- **Flight ring: times from the game's data.** Every route counts down from the first flight: the
  time comes from the game's own flight paths (each hop's length, mined from the WoW Forever client's
  taxi tables, at flying speed, plus any stops), added up over every hop of the trip. The ring no
  longer learns route times from your flights, so "Timing route", "Announce new route times" and
  "Forget flight times" are gone. A route that isn't in the data counts up ("No route data").
- **Target cast ring** (new; on by default). While your target casts, the ring fills (it drains
  for a channel) with the spell's icon, the time left and the caster's name. A cast you can't
  interrupt turns the ring gray and says "Can't interrupt". It turns green when the cast goes off,
  or red when it's interrupted, flashing the part that was lost. Switching targets follows the new
  target's cast. When combat hides the target's cast times, the ring times it from how long that
  spell took before (learned whenever it can see) or its listed cast time; failing both, the
  game's own timer fills the ring (with the game's countdown in the middle). Three-quarter and
  half arcs get a sweeping disc in the middle instead. `/circ targetdebug` shows what's hidden.
  Targeting yourself shows your own casts too (Target casting > Include yourself, on by default).
  Options: Enemies only, Show caster's name, its own colors, and Hide the game's
  target cast bar. Preview with `/circ target`.
- **Corpse ring: revive animation** (on by default; Corpse > Revive animation). When you come
  back to life in your own body (resurrecting at your corpse, or accepting a resurrect as a
  ghost), your soul, a pale flickering orb with a smoky tail, drifts down into the ring while
  wisps of ghost light rise from around it and stream in. The ring draws in as the soul sinks into
  its middle, warms from the ghost color to the "in range" color, and a heartbeat thumps out, each
  beat flashing the ring and rolling a wave outward. Then the last of the ghost rises away as mist.
  Not played at a spirit healer. Shown in the corpse ring's preview.
- **Discovery animation: symmetrical.** The ring closes down both sides at once, from the top to the
  bottom, with the compass ticks and sparks mirrored left to right, and a pair of glints bounces up
  and down both sides of the ring.
- **Fixed: a profession skill-up could pop two rings,** the first with the generic anvil icon, when
  the game listed the same skill under two IDs. One ring now, with the profession's own icon.
- **Fixed: rings could be moved outside edit mode.** Dragging and right-click reset now only work in
  edit mode.

## 1.1.0

- **Fixed: the pet XP ring never showed.** It listened for pet XP changes on the wrong unit. It also
  catches up after a fight now, when the game hid your pet's XP during it.
- **Campfire ring** (new; on by default). While you rest at a campfire (the Welcoming Campfire
  buff), the ring fills and counts down until you're Well Rested, then turns "Well Rested!" and
  bursts. Firelight flickers in the middle with embers rising through it (Campfire > Firelight and
  embers). Preview with `/circ camp`.
- **Food & Drink ring** (new; on by default). While you eat or drink, the ring fills as the food
  or drink buff runs, counts down what's left and bursts when it's done. Eating sends steam curling
  up through the ring, and every chomp takes a tooth-marked bite out of the end of the fill with
  crumbs flying; drinking fills its middle with water that rises as you drink and
  sloshes with every gulp (Food & Drink > Animations). Eating and drinking at once splits the
  ring: eating fills up the left side and drinking up the right, each with its own buff and its
  own effects on its half. Preview with `/circ food`.
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
