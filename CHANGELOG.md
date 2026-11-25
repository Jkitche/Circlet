# Changelog

## Unreleased

- **Health & power rings** (new; Combat & casting > Health & power, and Target health). Your
  health round the ring with your mana, rage, energy or focus in a thinner band inside it, and the
  same for your target with its name and level (players in their class color, creatures red,
  yellow or green by how they feel about you). The health in the middle as a percentage, the
  number, both, or both on two lines; the power under it. Optionally your or your target's
  portrait fills the middle. Shows always, in combat or when anything isn't full, or only in
  combat, and can hide the game's own player and target frames.
  - **Smooth changes**: the bands ease to a new value like the XP ring. WoW Forever hides health
    and power from addons (your own too, even out of combat), so the game does the easing: the
    band is built from short pieces, each cut by a mask that follows a status bar the game eases,
    turned towards the ring's centre so the moving edge is a clean radial cut.
  - **Damage trail and heal glow**: where the values can be read, health you lose stays behind as
    a red trail for a moment and then drains after the band, and health you gain glows softly as
    it fills in.
  - **Flash on big hits**: the health band flashes red for a moment when one hit takes 15% or
    more (adjustable). When the values are hidden the game won't say how big a hit was, so then
    critical and crushing hits count.
  - **Right-click menu**: right-click a ring for the game's own menu for that unit, as on its
    frame (Set Focus, raid marks, whisper, inspect...). Left clicks still go through to the world.
  - **Click to target yourself** (your ring): left-click your ring to target yourself, as on
    your player frame. On by default; turn it off to let left clicks go through to the world.
  - **Level badge**: the level on a gold-rimmed disc, at the bottom left of your ring and the
    bottom right of the target's (on by default for both). Enemies' levels are coloured the way
    the game's target frame and nameplates colour them; friendly units' are always yellow.
  - **Effects** (each with its own switch in the ring's new Effects box, all on):
    - *Combo points* (target): five pips over the ring that pop as they light and pulse gold at
      five, for rogues and druids.
    - *Raid marker* (all three rings): the skull, cross, star... at the top left of the ring.
    - *Aggro warning* (target): a red glare round the ring while it's targeting you.
    - *Execute range* (target): the ring throbs red-orange below 20% health.
    - *Low health heartbeat* (yours): a red lub-dub below 30% health.
    - *Death*: the ring cracks and darkens with a skull over it; your ghost glows pale with
      wisps drifting up.
    - *Combat start* (yours): a gold ring bursts outward as combat starts.
    - *Heal shimmer*: green sparkles race up both sides when a heal lands.
    - *Jolt on crits*: the ring jolts on a critical or crushing hit.
    - *Block, dodge, parry*: a shield, a whoosh round the ring, crossed blades.
    - *Energy tick* (yours): a spark runs round the energy band once per energy tick, so you can
      time abilities to it.
    - *Rage embers* (yours): embers fly off the rage band as rage comes in.
    - *Full mana shine* (yours): a soft shine on the mana band while it's full.
    - *Elite glint* (target, target of target): a glint circles elite rings (silver for rares).
    - *Skinnable* (target): a pelt badge at the top right when the target's corpse can be skinned
      (or herbs, ore or parts gathered), glowing in the tooltip's difficulty color. The game only
      says so once a corpse is looted, so kinds of creature seen skinnable before are remembered
      and get a faint badge while alive or not yet looted; a skinned corpse drops it.
    - *Quest target* (target): a yellow ! at the bottom left when the target is part of one of
      your active quests, with the objective's progress (3/10) under it when the game shows it.
    Health and mana thresholds work in combat too: the hidden percentage runs through a step
    curve straight into the effect's opacity, as the rings fill.
  - **Damage and healing numbers** (your ring and the target's): each hit and heal the unit takes
    floats up off the top of the ring and fades: damage (red on yours, white on the target's),
    crits bigger and gold with a pop, heals green with a +, and misses as words (Dodge, Parry,
    Block...). In combat the game hides the amounts from addons, so they're handed to the game to
    draw as they are. On by default; turned on or off at the top of the ring's Effects box, with a
    Direction dropdown (up, down, left or right) for which side they float off; sized in the Text
    sizes box.
  - **Elite indicator** (target and target of target): the game's own target-frame dragon round
    the level badge: the gold dragon for elites and world bosses, the silver one for rare elites,
    and the silver frame for rares. The badge takes its colors from the dragon (its gold or
    steel rim, and the dark of its shading for the outline and inside) so the two blend into
    one piece. On by default; off in the ring's General box.
  - **In-combat indicator** (your ring): crossed swords at the top right while you're in combat.
  - **Target of target ring** (new): a smaller ring beside the target ring for who your target is
    after, with its health, power and name. Can hide the game's target of target frame.
  - `/circ hpdebug` and `/circ masktest` report what this client lets the rings see and do (for
    bug reports).
- **Text sizes for every ring** (Look & position > Text sizes). Every piece of text on every ring
  has its own size, 50% to 200% of its usual size (which still follows the ring's): the title,
  main text and bottom line on most rings, the name, gain, gain %, progress and bottom line on the
  pop-up rings, and so on. At 100% everything is exactly as before.
- **Weapon imbue ring** (new, shamans; Combat & casting > Weapon imbue). While your main hand
  has a weapon imbue, the ring drains over it with the imbue's name and the time left, turning
  red in the last 30 seconds, and says Faded when it's gone. Each imbue has its own animation:
  Rockbiter sends shaded stones orbiting the ring with grit falling away, Flametongue turns the
  ring to molten lava (lumps of glowing, cracked crust creeping round, bubbles popping, drips
  falling off the bottom), Frostbrand sets ice crystals twinkling round the band with snow
  drifting down, and Windfury whips streaks of wind round the ring in gusts. Particles move at
  their own speeds, some each way round. The imbue is read off the weapon's tooltip first, so
  the right animation shows even for ranks Circlet doesn't list.
- **Soulstone ring** (new, warlocks; Group > Soulstone). When you put a soulstone on someone,
  the ring drains over its 30 minutes with their name and the time left, turning red in the
  last five, then says Expired, or Used if it's gone early. Out of combat it checks the stone is
  still on them and takes the time from the buff. It survives a reload or logging out, and out
  of combat it reminds you when you have a soulstone ready and none is out.

## 1.4.0

- **Hearthstone ring** (new; Travel & survival > Hearthstone). While you cast your Hearthstone
  (or Astral Recall) the ring fills and counts down with the place you're bound to, then says
  Home! and bursts. With Swirling portal on (the default), three spiral arms of arcane motes turn
  in its middle, two comets race round the ring, and everything speeds up and brightens as the
  cast nears its end; when it goes off the swirl collapses into a flash and a shockwave rolls
  out. The cast ring leaves these casts to it (turn the hearthstone ring off to have the cast
  ring show them again).
- **Crafting animations** (new; on by default, Crafting > Profession animations). Each of WoW
  Forever's crafting professions gets an animation of its own on the crafting ring, worked out
  from the trade skill window you craft from. Alchemy: bubbles rising through a shifting potion
  glow. Blacksmithing: a hammer striking the end of the fill, throwing sparks. Engineering:
  crackling lightning. Enchanting: orbiting runes and an arcane beam. Tailoring: a needle laying
  stitches along the fill. Leatherworking: the fill turns to worn, cracked, tooled leather with
  brass studs, and a needle laces a thread along it in wide, sweeping waves. Cooking: flames
  under the ring and steam rising. First Aid: a heartbeat glow and rising crosses. Smelting:
  molten metal and embers. Poisons: dripping venom. Each item made pops at the end of the fill,
  and a finished batch bursts in the profession's colors. The preview plays each profession in
  turn, or pick one under Preview animation. The crafting ring now also follows the older Craft
  window (Enchanting on older clients).
- **More ring animations** (new; on by default, each ring's Animations option):
  - **XP**: as XP comes in, a glowing comet rides the end of the fill in its color (blue while
    rested, purple after), shedding sparkles, and flares where the fill lands (XP > Effects >
    Gain effect).
  - **Mana regen**: while the five-second rule holds your regen back, a spark charges up at the
    end of the fill with motes drawn into it; when regen starts again, motes of mana spiral in
    and the spell's icon bursts. During Innervate the mana keeps flowing in.
  - **Flight**: the player arrow flies along the end of the fill with a contrail, clouds drift
    through the ring and wind streaks rush past; landing, the arrow touches down in a glow and a
    puff of dust and the clouds part.
  - **Loot rolls**: two dice under the ring rattle and hop while you decide (harder, over a red
    glow, when time's nearly up), then tumble and land on their numbers when you roll. Rare
    items and better get sparkles in their quality color.
  - **Timed quests**: an hourglass. Sand trickles from the end of the fill and piles up in the
    bottom of the ring as time runs out, reddening and pouring faster near the end.
  - **Profession skills**: a spark rides the fill shedding glitter in the profession's colors,
    then bursts with motes floating up; a new tier or the cap sends a gold shimmer round the ring.
  - **Weapon skills**: a steel swoosh slices across the end of the fill, then a clang and a spray
    of sparks; capping a skill sends a blade glint round the ring.
- **Flight times fixed.** The flight ring counted down about 11% too fast, finishing before you
  landed. Its flying speed is now measured from 13 real flights (one and two hops, up to 7½
  minutes), which all flew at 30 yards a second; it now lands within a second of the real time.
- **/circ showxp** (or /circ myxp): brings the XP ring up for a few seconds at your current XP,
  even when it's hidden or its text has faded, and prints your XP to chat (level, XP into it and
  to go, rested).
- **New options window.** Redesigned from scratch in Circlet's own dark-and-gold look. On the
  left: General, Profiles, Edit all rings, What's new and the Setup wizard, a search box, and
  every ring sorted into six folders (Progress, Combat & casting, Group, Travel & survival,
  Professions, Rest & utility), each with a dot that turns the ring on or off with a click. On
  the right: the page's title and description, tabs (a ring's settings, and its look &
  position), and its settings in titled sections, two to a row, with on/off switches, sliders
  you can also type a number into, dropdowns and color swatches; hover any setting for what it
  does. Each ring's Edit mode, Preview and Reset buttons sit along the bottom, and a Window
  scale slider sizes the whole window. A folder's own page has a switch for each of its rings.
- **XP ring settings follow its mode.** The XP ring's page only shows what applies: the
  minimap border's distance and layering when it's on, the idle-text options when the ring is
  always shown, how long it stays and showing while resting only when it pops up, and no size
  or position around the minimap.
- **Matching windows.** The setup wizard, What's new and the session summary use the options
  window's colors, switches and buttons. The summary now leaves out anything that hasn't
  changed this session, and says so when nothing has yet.
- **Swing timer ring** (new; Combat & casting > Swing timer). While you auto-attack, the ring
  fills over your weapon's speed and counts down to your next melee swing, then says Ready
  until it lands, with how the last swing went underneath (Hit, Crit, Glancing, Miss, Dodged,
  Parried, Blocked). Heroic Strike, Cleave, Maul and Raptor Strike count as the swing, finishing
  a spell with a cast time restarts it, and haste or slows rescale it. The game keeps the combat
  log from addons, so swings are spotted from the hits your target takes; in a group someone
  else's hit can now and then be taken for yours. Main hand only.
- **Shot timer ring** (new; Combat & casting > Shot timer). While Auto Shot repeats (or a wand's
  Shoot, or Throw), the ring fills over your ranged weapon's speed and counts down to the next
  shot. For Auto Shot's last half second, its aim, when moving holds the shot back, the ring
  turns red and says Aiming, or Hold still if you're moving.
- The swing and shot timer rings can hide WoW Forever's own swing timer bars (each ring's
  "Hide the game's ... bar" option, off by default). If the bars can't be found, the option
  turns the game's Swing Timer setting off instead, and puts it back when you turn it off.
  `/circ swingbars` shows what was found.
- Finishing "Edit all rings" says "All ring positions saved." once instead of a line per ring.
- The "New in" page lists everything in the release, not just the new rings: new animations and
  options (each with its on/off box and Show), then fixes and changes.

## 1.3.2

(1.3.0 and 1.3.1 were tagged but their releases didn't go out; this is their first release.)

- **Gathering animations** (new; on by default, Gathering > Profession animations). Each gathering
  profession has an animation of its own at the gathering ring's top right, using the game's own
  cursor art for the tools, held by their handles. **Skinning**: a knife slashes along the ring in
  quick strokes, flicking off tufts of fur that tumble away; when the skin comes off it makes one
  long last slice and a cut runs round the whole ring, spraying fur off all of it. **Mining**: a
  pickaxe swings at the ring, raising and striking with a flash and a crack of light that throws
  sparks and chips of rock; when the vein breaks the whole ring flashes and rock and sparks burst
  off all round. **Herbalism**: pruning shears snip at the ring, each snip cutting leaves and
  petals loose to flutter down; the last snip sends a gust of them off the whole ring. The
  gathering preview (`/circ gather`) now shows a skinning, a mining and an herb.

- **Fishing ring** (new; on by default). While your line is out the ring counts down the cast,
  its fill bobbing around the countdown like a float, with a tug now and then (the ring itself
  stays put). The game doesn't tell addons when a fish bites, so the ring flashes "Watch the
  bobber!" in the windows where bites usually come (about 17, 13, 7 and 3 seconds
  left; turn that off under Fishing > Flash in bite windows). Then it shows what you caught, or
  "Got away". The gathering ring leaves fishing to it (and takes it back if you turn it off).
  **Right-click to reel in** (off until you turn it on): while the line is out and you're out of
  combat, a right-click anywhere on the screen clicks the bobber, using the game's soft-target
  interact. Your right-click and interact settings go back to normal as soon as the line comes in or
  a fight starts. Preview with `/circ fish`.

- **Mana regen ring** (new; on by default). The five-second rule: each time you cast a spell that
  costs mana, the ring fills over the five seconds your mana regen is stopped, counting down to
  when it starts again, then lights up and fades. It goes by the spell's cost (your mana itself is
  hidden from addons), remembering which spells cost mana for when the cost is hidden mid-fight.
  Casts made free by Clearcasting (mage, druid, shaman), Inner Focus or Spirit of Redemption don't
  start it, since they don't stop regen; during Innervate it says "Innervated". Preview with
  `/circ regen`.
- **Timer ring** (new). A countdown you start yourself: `/circ timer 5m Tea` (also `1:30`, `90`,
  `1h20m`, `10 min Pull`...), or the 1, 5 and 10 minute buttons on its options page. The ring drains
  with the label and the time left and a pocket watch icon, pulses in the last 10 seconds, and when
  time's up it bursts, plays a sound and shows the label in big text on screen (each optional).
  `/circ timer +2m` adds time, `/circ timer stop` stops it, `/circ timer` says what's left. A running
  timer carries on through a reload or a relog. Stays up in combat; Icon as background works too.
- `/circ timer` now starts a timer; the timed quest ring's preview is `/circ timed`.
- **Target cast ring: progress fills the ring even when combat hides the cast times.** The ring's
  own segments now light up as the cast goes, read from the game's hidden cast duration through
  curves, so every shape (ring, three-quarter, half arc), style and direction fills as usual, with
  the game's countdown in the middle; a channel drains. This replaces the filled circle that arcs
  used to get. Where the game doesn't allow that, it falls back to the game's own sweep.
  `/circ targetdebug` says which way the last cast was shown.
- **Flight log** (for checking flight times): `/circ flightlog` lists your last flights, how long
  each was predicted to take and how long it really took.

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
