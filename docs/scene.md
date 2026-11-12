# The scene: effects and presences

Plugins used to change only fish. This layer lets them change the aquarium itself, still by sending data and never
drawing anything: **effects** (one-off moments, like fireworks or a lightning flash) and **presences** (creatures and
objects that live in the tank while the plugin keeps them there, each with a state and the text the plugin sends).

The code is in `Sources/Fishbots/Scene.swift` (simulation and sprites), `TankProtocol.swift` (parsing),
`Labels.swift` (their labels), `AppDelegate.swift` (hover, click), `SourceCard.swift` (the card of the lights on the
glass) and `ShaderPresences.swift` (the drawings, sprite kinds 25–31 and 45).

## Effects

```json
{"source":"ci","effect":"fireworks","label":"deploy meu-site","x":0.6}
```

| Field | |
|---|---|
| `effect` | the effect's name (table below) |
| `label` | optional: shown at the top for a few seconds, with the effect's icon |
| `x`, `y` | optional: where (0…1, from the left and from the bottom). Default: somewhere in the middle |
| `color` | optional: `"#rrggbb"`, for the effects that have a color (without it, the theme's color for that effect, if it has one) |
| `sound` | optional: another voice (see **Sound**), or `"none"` for silence |

| Effect | What happens |
|---|---|
| `food` | food falls from the surface and the fish come to eat (the same as `event`) |
| `fireworks` | three bursts of light, one after the other |
| `whale` | the whale passes in the distance, with its song (only in themes that have the whale) |
| `splash` | a splash on the surface |
| `ink` | a cloud of ink |
| `bubbles` | a column of bubbles rising from the sand |
| `sparkle` | a ring of sparkles |
| `ring` | a ring spreading in the water |
| `scare` | the nearby fish get startled and flee |
| `pearl` | a pearl of the day on the sand (the `label` becomes its title) |
| `lightning` | the water lights up in two quick flashes |
| `quake` | the tank shakes and the sand rises from the bottom |
| `school` | a school of small fish crosses the tank |
| `shooting-star` | a streak of light crosses near the surface |

An unknown effect is an error in the response, so a plugin finds out right away.

## Summoning a passing creature

The creatures that pass now and then (the turtle, the whale, the sunfish, the manatee, and a pack's creatures that
cross or pass) choose their own moment. `summon` brings one by now, if it lives in the current theme:

```json
{"source":"ci","summon":"whale"}
```

`"all"` calls every one of them. Nothing of that kind passing by in this theme is an error in the response.
From the terminal: `fishbots summon turtle`.

## Presences

```json
{"source":"k8s","presence":"prod","kind":"shark","state":"error","label":"prod",
 "detail":"3 pods em CrashLoop","link":"https://grafana…","value":0.4}
{"source":"k8s","presence":"prod","state":"end"}
```

| Field | |
|---|---|
| `presence` | its id within the source (like `entity` for fish) |
| `kind` | what it is (table below). Needed when it's created; it can change later |
| `state` | `born busy idle waiting ok alert error done`, or `end` to leave (`"party":true`: leaves with a sparkle). Default: `ok` |
| `label` | the text under (or above) it |
| `detail` | a second line: shown on hover, for a few seconds after it changes, and always while it needs you (`waiting`, `alert`, `error`) |
| `link` | opened on click (`http`/`https`) |
| `value` | 0…1, for the kinds that show a quantity (hourglass, battery); the label shows the percentage when there is no `detail` |
| `color` | `"#rrggbb"`: its color (each kind has a default) |
| `x` | 0…1: where it stays (objects on the sand) or where it swims around. Default: a spot picked from its id |
| `sound` | its voice (see **Sound**), or `"none"` for silence. Default: the kind's voice. It stays until changed |

The protocol is the same as for fish: send it again to update, send `end` to remove it. Script plugins with an
interval (`name.5m.sh`) get the same clean-up as fish: a presence that isn't in the latest successful run leaves.

### Kinds

| Kind | Moves | Good for |
|---|---|---|
| `shark` | patrols across the tank | something wrong and big (production down) |
| `submarine` | crosses slowly, deeper | a long job (backup, migration, deploy) |
| `turtle` | swims across, unhurried | something slow and steady |
| `jellyfish` | drifts up and down | a soft indicator |
| `seahorse` | bobs in place | a person or a message |
| `crab` | walks on the sand | something busy and small |
| `starfish` | stays on the sand | a static marker |
| `bottle` | floats at the surface, bobbing with the waves (half sunk in `error`) | a message, an issue, a note |
| `hourglass` | stands on the sand; `value` is the sand left on top | time left, a countdown |
| `anchor` | drops from the top and stays | something pinned, a blocker |

Packs can add kinds of their own (a drawing in Metal plus how it moves): see `presences` in
[extensions.md](extensions.md#presences-from-packs). Plugins use them like these, by id, in any theme. Send
`"fallback"` with a built-in kind for people who don't have the pack: it stands in, and turns into the pack's kind when
the pack is installed (`{"kind": "floating-lantern", "fallback": "bottle", …}`). If a pack is removed or paused, its
presences are drawn by a built-in kind that moves the same way until it comes back.

A theme can dress the built-in kinds its own way (in the Japanese pond a `bottle` floats as a paper lantern): the
meaning stays, only the drawing changes. Send `"override_theme": true` when your drawing matters (the shark for
production down): it's shown as sent in every theme.
| `flag` | stands on the sand, waving; its cloth takes the state's color | a status (green/yellow/red) |
| `helm` | a ship's wheel fallen on the sand; its hub takes the state's color and it turns while `busy` | the one or two things you steer and want in sight |
| `pilot` | a small light on the side glass, in the state's color, next to the others from its source (see **Lights on the glass**) | many things you only need to hear from when they break: clusters, sites, jobs |
| `chest` | stays on the sand; glows when `done` or `waiting` | a goal, a reward |
| `battery` | lies on the sand; `value` is the charge | a level that runs out |
| `moray` | lives in a burrow in a rock on the sand: just its snout at the door while `ok` or `idle`, out and swaying in any other state | something that's always there and speaks up now and then (the aquarium's own assistant is one) |

### Lights on the glass

`pilot` is for the long lists: eight clusters, twenty sites. Each one is a small lamp stuck on the side glass, out of
the fish's way; a source's lights stay together, one under the other, and each new source takes the emptier side (a
second column starts when a side is full).

- The lamp is the state: green `ok`, blue and breathing `busy`, gray and nearly out `idle`, yellow `waiting`, amber
  `alert`, red `error`. `color` tints its bezel.
- While all is well it shows no text. When it needs you (`waiting`, `alert`, `error`) it grows, pulses and shows its
  `label` and `detail` beside it; a state change shows them for a few seconds; hover shows them any time.
- A click opens a card with everything that source keeps on the glass, what needs you first, each with its detail;
  a row with a `link` opens it.
- It makes no bubbles and no ink, and its sounds are the same as any presence's.

A pack can draw the light its own way (a presence with `"motion": "glass"`), and a theme can dress `pilot` in it.

### States

Every kind follows the same rules, so a plugin only says what's happening:

| State | How it looks | How it moves |
|---|---|---|
| `born` | arrives with a burst of bubbles (objects drop from the surface) | normal |
| `ok` | normal | normal |
| `idle` | dimmer | slower |
| `busy` | small bubbles rise from it | faster |
| `waiting` | yellow glow, pulsing; detail always shown | swimmers come to the front of the glass and wait |
| `alert` | amber tint and glow | normal |
| `error` | faded, reddish; ink now and then; detail always shown | swimmers sink and slow down |
| `done` | a ring of sparkles when it arrives | normal |

A state change also leaves a ring in the water. Coming back from `error` makes a little sparkle.

### Text

Like the fish labels, and following the labels setting (L: minimal, full, none):
- the `label` always shows (in "none", nothing shows but on hover, even while it needs you: its glow and its color
  already say so);
- the second line shows the `detail` (or the state's name) in the state's color while it needs you, and for a few
  seconds after anything changes;
- on hover: everything, plus "↗" when there is a link.

## Sound

Presences sound like the fish do: only when something changes, never while they just work.

| When | What plays (over the voice's note, in the music's current key) |
|---|---|
| arrives | the voice once, softly |
| `waiting` | a question going up a fifth; again every 2.5 min while it waits |
| `alert` | a tritone |
| `error` | a step down |
| `done` | a major arpeggio |

Each kind has its own voice, so you can tell who called without looking:

| Kind | Voice | | Kind | Voice |
|---|---|---|---|---|
| shark | `bass` (low, with a pad) | | bottle | `glass` (clink) |
| submarine | `sonar` (ping with echoes) | | hourglass | `tick` (tick-tock) |
| turtle | `flute` | | anchor | `clang` (low bell and bass) |
| jellyfish | `pad` | | flag | `soft` |
| seahorse, starfish | `kalimba` | | chest | `bell` |
| crab | `tap` | | battery | `bubble` |
| helm | `clang` | | pilot | `soft` |

Effects have theirs too: `food` and `fireworks` an arpeggio of the chord that's playing, `whale` its song, `lightning`
`thunder`, `quake` `rumble`, `school` `run` (a quick scale), `shooting-star` `glissando`, `pearl` and `sparkle`
`chime`, `splash` and `bubbles` `bubble`, `ring` `tap`, `scare` `glass`, `ink` `bass`.

A plugin can pick any voice with `"sound"`: `arpeggio`, `whale`, `bass`, `sonar`, `glass`, `tick`, `clang`, `bell`,
`chime`, `kalimba`, `flute`, `pad`, `soft`, `pluck`, `tap`, `bubble`, `thunder`, `rumble`, `run`, `glissando`, or
`none`. An unknown voice is an error in the response.

On your side: focus mode silences them all, and `alert`/`error` sounds follow the attention rules (Preferências →
Atenção, or `config.json`), like the fish: a source set to `ambient` for errors doesn't play them.

To hear everything: `scripts/scene-demo.sh` (or `scripts/scene-demo.sh effects`).

## Continuous controls (gauges)

Some gauge names change the whole scene, whatever the source (the highest value wins when several send it):

```json
{"source":"weather","gauge":"rain","value":0.6}
```

| Gauge | 0 … 1 |
|---|---|
| `rain` | thin slanted streaks in the air above the water, drops ringing on the surface and their rings of light on the sand, a darker day |
| `waves` | a calm surface … a rough one (floating bottles ride it; the bands of light it throws on the sand sharpen) |
| `temperature` | cold (bluer water) … 0.5 neutral … warm (amber, greener water) |
| `fog` | a haze over everything |

The older ones still work: `disk` (murky water), `mac:cpu` (current), `mac:battery` / `mac:charging` (the battery on the sand).
`"value": null` removes a gauge (`bin/fishbots gauge <source> <name> end`); one not sent for an hour goes away by itself,
and a script plugin with an interval loses the gauges it stopped sending, like its fish and presences.

## Not yet

- Presences from packs (new kinds with their own `.metal`, like pack fish).
