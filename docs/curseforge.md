<!-- The project description for the CurseForge page: paste it into the Description field
     (Markdown). Screenshots go in the project's Images tab. -->

# Circlet

**Progress rings for WoW Forever.** Rings pop up and fill as you play, then fade away, so you
see your progress without staring at bars. Or keep the XP ring up as your XP bar, even wrapped
around the minimap. Most rings come with an animation of their own.

## New in 1.4.0

- **Hearthstone ring**: a swirling portal of arcane motes and racing comets while you cast home,
  collapsing into a flash when it goes off.
- **Health & power**: your health and power, your target's and its target's, with combo points,
  raid markers, an aggro warning, execute range, a low-health heartbeat, energy ticks, damage
  and healing numbers, and the elite dragon.
- **Swing timer** and **shot timer** rings: your next melee swing, Auto Shot, wand shot or throw,
  with how the last swing went and a warning to hold still through Auto Shot's aim.
- **Crafting animations** for every WoW Forever profession, worked out from the trade skill
  window you craft from.
- **More ring animations**: an XP comet, a charging spark for mana regen, a flying arrow and
  clouds on flights, dice for loot rolls, an hourglass for timed quests, and effects for skill-ups.
- **Flight times fixed**: the flight ring now lands within a second of the real time.
- **New options window**: every ring in a searchable sidebar with an on/off dot, tabs, and each
  ring's settings two to a row with switches, sliders and color swatches. The setup wizard, What's
  new and the session summary got the same look.
- **/circ showxp**: brings the XP ring up for a moment to check your XP, even when it's hidden.

## Progress

- **XP**: fills with each gain, colored by rest state, with the rested band ahead of you and a
  glowing comet riding the fill as XP comes in. A level-up effect (gold or rainbow), a resting
  zZZ at inns, and how much rested XP you gained when you leave. Optionally always on, with its
  text hidden when idle, or as a minimap border. `/circ showxp` brings it up for a moment
  whenever you want to check.
- **Quests**: each objective's progress ("Screecher Feather 5 / 8"), a "!" when one's done and
  a "Ready to turn in" alert. Pin any quest from the quest log to give it its own ring.
- **Professions** and **weapon skills**: every skill-up, new training tiers, and "capped", with
  glitter in the profession's colors, or a steel swoosh and sparks for weapons.
- **Reputation**: gains, losses and new standings, with the faction's icon.
- **Pet XP** for hunters.

## Combat & casting

- **Casts**, timed even in combat, glowing in the spell's school: embers for fire, snowflakes for
  frost, motes for arcane, wisps for shadow, a swirl for nature, rays for holy. Resurrections
  rise in holy light and finish with a pillar of light.
- **Target casting**: what your target is casting, and whether you can interrupt it.
- **Swing timer** and **shot timer**: counts down to your next melee swing, Auto Shot, wand shot
  or throw, with how the last swing went and a warning to hold still through Auto Shot's aim.
- **Mana regen**: the five-second rule, a spark charging up until your regen starts again.
- **Ammo and soul shards**: a warning as you run low, or a countdown on every shot.
- **Totems** (shamans): one small ring per element.
- **Weapon imbue** (shamans): time left on your weapon imbue, with orbiting stones, molten
  lava, ice and snow, or whipping wind depending on which it is.
- **Soulstone** (warlocks): who has your soulstone and how long it has left, with a reminder
  when you have one ready and none is out.

## Group

- **Loot rolls**: the time left to roll, with two dice rattling while you decide and tumbling
  when you roll.
- **Ready checks**: time left to answer, and how many are ready.

## Travel & survival

- **Flight paths**: counts down to landing, timed from the game's own flight path data, with your
  arrow flying through clouds along the ring.
- **Hearthstone**: a swirling portal of arcane motes while you cast home.
- **Timed quests**: an hourglass, sand piling up as time runs out.
- **Corpse runs**: distance to your body, an arrow pointing to it, and when you can resurrect.
- **Breath**, fatigue and Feign Death, with bubbles.

## Professions

- **Crafting** batches, with an animation for each profession: bubbling potions for Alchemy, a
  hammer and sparks for Blacksmithing, lightning for Engineering, runes for Enchanting, stitches
  for Tailoring, laced and studded leather for Leatherworking, flames for Cooking and more.
- **Gathering** (mining, herbalism, skinning) with what you got.
- **Fishing**: the bobber's time, flashing when a bite can come.

## Rest & utility

- **Food & drink**: fills as you eat or drink, with a bite out of the ring on every chomp.
- **Campfire**: resting at a camp, counting down to Well Rested, with firelight and embers.
- **Clock** (optional): an always-on clock face, local or realm time.
- **Timer**: a countdown you start yourself, like `/circ timer 5m Tea`.

## Make them yours

- A clean options window: every ring in the sidebar with an on/off dot, a search box, and each
  ring's settings laid out on one page, with a preview and edit mode a click away.
- Per ring: style (smooth, segmented, thin), shape (full ring, arc, half arc), rotation, fill
  direction, solid or gradient fill, black border, opacity, size and colors. Or apply one ring's
  look to all.
- Show a ring's icon as a badge on its edge or filling its middle.
- Edit mode shows each ring live while you change it; drag rings into place with a snap grid.
  Rings that pop up together slide apart instead of overlapping.
- Hide any ring in combat, or hide the game's own bar a ring replaces (XP bar, cast bar,
  breath bar, swing timers...).
- Turn any ring's animation off if you prefer it plain.
- Profiles per character.

## Extras

- A setup wizard the first time you log in, and a What's new page after each update.
- A welcome animation when you log in, and a "Discovered" flourish when you explore a new area.
- A session summary of everything you gained: XP, levels, quests, skills, reputation, flights,
  deaths and money.

## Commands

`/circ` (or `/circlet`) opens the options. `/circ help` lists the rest: a preview for every ring,
`/circ edit` to arrange them, `/circ setup` for the wizard, `/circ summary` for this session's
gains.

No other addons needed.
