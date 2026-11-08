# Fishbots pack reference

## A complete pack.json (the Japanese pond)

```json
{
  "id": "koi",
  "name": "Lago japonês",
  "names": {
    "en": "Japanese pond"
  },
  "version": "1.7",
  "author": "Fishbots",
  "license": "MIT",
  "description": "Um lago japonês: carpas koi em quatro variedades, lanterna de pedra, vitórias-régias com lótus, sapos, girinos, camarões e música zen.",
  "descriptions": {
    "en": "A Japanese pond: koi in four varieties, a stone lantern, lily pads with lotus, frogs, tadpoles, shrimp and zen music."
  },
  "themes": [
    {
      "id": "koi-pond",
      "name": "Lago japonês",
      "names": {
        "en": "Japanese pond"
      },
      "visualizer": "surface",
      "music": "zen",
      "fauna": [
        "snail",
        "turtle",
        "frog",
        "tadpoles",
        "shrimp"
      ],
      "scenery": [
        "rock",
        "lantern",
        "lilypad",
        "chest"
      ],
      "looks": {
        "chest": "shrine",
        "bottle": "floating-lantern",
        "oval": "koi",
        "slender": "koi",
        "flag": "koinobori",
        "helm": "suisha",
        "shark": "namazu",
        "betta": "ryukin",
        "pebble": "river-stone",
        "seashell": "snail-shell",
        "mote": "petal"
      },
      "background": {
        "metal": "background.metal",
        "function": "draw_koi_background",
        "replaceReef": true
      },
      "water": {
        "deep": "#0b2420",
        "shallow": "#3f7d62",
        "rays": "#cfe8b0",
        "raysStrength": 0.18,
        "caustics": "#e8f5c8",
        "causticsStrength": 0.07,
        "surface": "#7fb88f",
        "murk": "#2e3a1c"
      },
      "weeds": {
        "count": 7,
        "farCount": 10,
        "far": "#25463a",
        "low": "#1d4a2a",
        "high": "#7aa64a",
        "shapes": [
          "reed",
          "blade",
          "leafy",
          "reed"
        ]
      },
      "sand": {
        "dark": "#3a3a34",
        "light": "#7a786a"
      },
      "jellyfish": false,
      "schools": [
        {
          "color": "#c9c2a0",
          "kind": "slender",
          "count": 12,
          "size": [
            6,
            7.5
          ],
          "pattern": 0,
          "depth": [
            0.2,
            0.55
          ]
        },
        {
          "color": "#d8b0b8",
          "kind": "oval",
          "count": 8,
          "size": [
            7,
            8.5
          ],
          "pattern": 0,
          "depth": [
            0.25,
            0.5
          ]
        },
        {
          "color": "#8a9a7a",
          "kind": "slender",
          "count": 5,
          "size": [
            12,
            15
          ],
          "pattern": 0,
          "depth": [
            0.6,
            0.8
          ]
        }
      ],
      "voices": {
        "chime": "koto",
        "glass": "koto",
        "kalimba": "koto"
      }
    }
  ],
  "chords": {
    "Fm(add9)": [
      5,
      8,
      0,
      7
    ],
    "Dbmaj7": [
      1,
      5,
      8,
      0
    ],
    "Csus4": [
      0,
      5,
      7
    ],
    "Bbm7": [
      10,
      1,
      5,
      8
    ]
  },
  "progressions": {
    "Pond": [
      "Fm(add9)",
      "Dbmaj7",
      "Bbm7",
      "Csus4"
    ]
  },
  "styles": [
    {
      "id": "zen",
      "name": "zen",
      "names": {
        "en": "zen"
      },
      "bpm": [
        50,
        60
      ],
      "progressions": [
        "Pond"
      ],
      "scale": [
        0,
        1,
        5,
        7,
        8
      ],
      "lead": [
        "koto",
        "koto",
        "flute"
      ],
      "accomp": "arpeggio",
      "accompTimbre": [
        "pluck",
        "soft"
      ],
      "notesPerBar": [
        1,
        3
      ],
      "swing": [
        0,
        0.05
      ],
      "keys": [
        0,
        2,
        5
      ],
      "energy": 0.2,
      "rest": 0.5,
      "visualizer": "surface"
    }
  ],
  "fish": [
    {
      "id": "koi",
      "name": "carpa koi",
      "names": {
        "en": "koi carp"
      },
      "metal": "koi.metal",
      "function": "draw_koi"
    },
    {
      "id": "ryukin",
      "name": "peixe-dourado ryukin",
      "names": {
        "en": "ryukin goldfish"
      },
      "metal": "ryukin.metal",
      "function": "draw_koi_ryukin"
    }
  ],
  "scenery": [
    {
      "id": "lantern",
      "name": "lanterna de pedra",
      "names": {
        "en": "stone lantern"
      },
      "metal": "lantern.metal",
      "function": "draw_lantern",
      "anchor": "sand",
      "size": 0.11,
      "extent": [
        0.6,
        1.0
      ],
      "at": [
        0.27
      ],
      "glowAtNight": true,
      "color": "#8c8c88"
    },
    {
      "id": "shrine",
      "name": "santuário",
      "names": {
        "en": "shrine"
      },
      "metal": "shrine.metal",
      "function": "draw_koi_shrine",
      "anchor": "sand",
      "size": 0.06,
      "extent": [
        1.0,
        1.0
      ],
      "color": "#8a8a88"
    },
    {
      "id": "lilypad",
      "name": "vitória-régia",
      "names": {
        "en": "lily pad"
      },
      "metal": "lily.metal",
      "function": "draw_lily",
      "anchor": "surface",
      "size": 0.06,
      "extent": [
        1.0,
        0.7
      ],
      "at": [
        0.12,
        0.3,
        0.52,
        0.71,
        0.88
      ],
      "color": "#4f8a3e"
    },
    {
      "id": "river-stone",
      "name": "seixo de rio",
      "names": {
        "en": "river stone"
      },
      "metal": "lantern.metal",
      "function": "draw_koi_stone",
      "anchor": "sand",
      "size": 0.012,
      "extent": [
        1.0,
        0.6
      ],
      "color": "#8a8070"
    },
    {
      "id": "snail-shell",
      "name": "concha de caramujo",
      "names": {
        "en": "snail shell"
      },
      "metal": "lantern.metal",
      "function": "draw_koi_snail_shell",
      "anchor": "sand",
      "size": 0.01,
      "extent": [
        1.0,
        0.75
      ],
      "color": "#a07850"
    },
    {
      "id": "petal",
      "name": "pétala",
      "names": {
        "en": "petal"
      },
      "metal": "lily.metal",
      "function": "draw_koi_petal",
      "anchor": "float",
      "size": 0.006,
      "extent": [
        1.0,
        1.0
      ],
      "color": "#ffffff"
    }
  ],
  "sounds": [
    {
      "id": "koto",
      "name": "koto",
      "file": "koto.wav",
      "root": "A3",
      "gain": 0.9
    }
  ],
  "presences": [
    {
      "id": "floating-lantern",
      "name": "lanterna flutuante",
      "names": {
        "en": "floating lantern"
      },
      "metal": "floating.metal",
      "function": "draw_koi_floating_lantern",
      "motion": "float",
      "size": 26,
      "extent": [
        0.8,
        1.0
      ],
      "color": "#c8503c",
      "sound": "chime"
    },
    {
      "id": "koinobori",
      "name": "koinobori",
      "names": {
        "en": "koinobori"
      },
      "metal": "japan.metal",
      "function": "draw_koi_koinobori",
      "motion": "sit",
      "size": 42,
      "extent": [
        0.8,
        1.0
      ],
      "color": "#e0503c",
      "sound": "soft"
    },
    {
      "id": "suisha",
      "name": "roda d’água",
      "names": {
        "en": "water wheel"
      },
      "metal": "japan.metal",
      "function": "draw_koi_suisha",
      "motion": "sit",
      "size": 34,
      "extent": [
        1.0,
        1.0
      ],
      "color": "#6a8ac8",
      "sound": "clang"
    },
    {
      "id": "namazu",
      "name": "namazu",
      "names": {
        "en": "namazu"
      },
      "metal": "japan.metal",
      "function": "draw_koi_namazu",
      "motion": "swim",
      "size": 58,
      "extent": [
        1.6,
        0.7
      ],
      "color": "#5a5a48",
      "band": [
        0.25,
        0.55
      ],
      "sound": "bass"
    }
  ],
  "fauna": [
    {
      "id": "frog",
      "name": "sapo",
      "names": {
        "en": "frog"
      },
      "metal": "creatures.metal",
      "function": "draw_frog",
      "behavior": "perch",
      "on": "lilypad",
      "size": 15,
      "extent": [
        1.2,
        1.0
      ],
      "count": 2,
      "color": "#5f8f3e"
    },
    {
      "id": "tadpoles",
      "name": "girinos",
      "names": {
        "en": "tadpoles"
      },
      "metal": "creatures.metal",
      "function": "draw_tadpole",
      "behavior": "school",
      "size": 7,
      "extent": [
        2.0,
        1.0
      ],
      "count": [
        6,
        9
      ],
      "speed": 18,
      "height": [
        0.15,
        0.45
      ],
      "color": "#3a3328",
      "shy": true
    },
    {
      "id": "shrimp",
      "name": "camarão",
      "names": {
        "en": "shrimp"
      },
      "metal": "creatures.metal",
      "function": "draw_shrimp",
      "behavior": "crawl",
      "size": 10,
      "extent": [
        1.6,
        1.0
      ],
      "count": [
        2,
        3
      ],
      "speed": 8,
      "color": "#d9806a"
    }
  ]
}```

Fish entries: `{"id", "name", "metal", "function"}`.

## A theme's own background and looks
A pack theme can draw its own far background and give the built-in pieces another look:

```json
{ "id": "koi-pond", …,
  "background": { "metal": "background.metal", "function": "draw_koi_background", "replaceReef": true },
  "looks": { "chest": "shrine" } }
```

- `background`: drawn over the water and behind the seaweed, by
  `float4 f(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra)`: uv 0…1 over the window
  (y up), t seconds, light the daylight (0…1), gaze the parallax (-1…1: move far things a little with it), water the
  water's color there (mix toward it for haze), extra.x the aspect, extra.y moonlight, extra.z the sand line's height at
  this x. `replaceReef` (default true) leaves out the distant reef the aquarium draws.
- `looks`: how the theme dresses built-in things, by id. The meaning stays, only the drawing changes:
  - a **piece of scenery** (`rock`, `shell`, `chest`, `coral`) drawn by one of the pack's scenery pieces, in the same
    place and with the same behavior (the chest still opens the summary). A chest's drawing gets how open it is in
    `extra.y` (instead of the seed) and glows while it's open. The piece doesn't need to be in the theme's `scenery`;
  - a **presence kind** plugins send (`"bottle": "floating-lantern"`): drawn as one of the pack's presences that moves
    the same way (checked on load), keeping its label, state, link and sound. A plugin that wants its own drawing
    sends `"override_theme": true`;
  - a **fish kind** (`"oval": "koi"`): the fish of that kind are drawn as the pack's fish. A kind someone picked by hand
    in the fish menu stays as picked. `"betta"` is the music fish (it keeps dancing and letting out notes);
    `"lanternfish"` the night lanternfish;
  - a **built-in creature** (`crab`, `turtle`, `snail`, `starfish`, `whale`, `jellyfish`): drawn as one of the pack's
    creatures (or, for the jellyfish, a presence), moving as always;
  - the **drifting bits** (`mote`, the marine snow; `bubble`; `food`): drawn as one of the pack's scenery pieces
    (`float` anchor), small; `t` turns them;
  - the **little things on the sand** (`pebble`, `seashell`, `pearl`): drawn as one of the pack's scenery pieces (sized
    by the app; a pearl's drawing gets the project's color as `col` and glows while it's new).

  People can turn this off in Preferências → Aparência ("Vestir presenças e peixes com o tema").

- `sky`: the light through the day. The color the hour casts over everything at `night`, `dawn`, `day`, the
  `golden` hour and `dusk` (multipliers: `[r, g, b]` may go over 1 to warm or brighten), the water's brightness at
  night and at midday (`"light": [0.5, 0.9]`), and how strong the `sun` and the `moon` are through the surface
  (1 is the usual):

  ```json
  "sky": { "night": [0.55, 0.68, 1.15], "dawn": [0.95, 0.92, 1.05], "day": [0.92, 0.98, 1.1],
           "golden": [1.0, 0.92, 0.95], "dusk": [0.75, 0.78, 1.1], "light": [0.45, 0.85], "sun": 0.5, "moon": 1.4 }
  ```
- `schools`: up to three decorative schools (the first swims in the middle, the second up high, the third low and
  far), each `{"color", "kind", "count", "size": [lo, hi], "pattern", "depth": [lo, hi]}`; `kind` may be a pack's fish.
  Without it, the usual neons, tetras and silversides.
- `jellyfish`: `false` leaves out the jellyfish that drifts around.
- `frost`: 0…1, ice creeping in on the glass from the sides and corners, as if the tank were freezing (the arctic uses 0.6).
- `voices`: the scene's voices (what presences and effects sound like, docs/scene.md) given another voice or one of the
  packs' recorded sounds: `{"chime": "koto", "kalimba": "marimba"}`. The crossing school effect uses the theme's first
  school.
- `foreground`: `false` leaves out the blurred seaweed tufts up front; a color tints them.
- `weeds.shapes`: the seaweed's shapes, mixed along the tank: `blade`, `kelp`, `leafy`, `reed` (straight, some with a
  cattail's head), `ribbon` (thin, dark, waving). Without it, blades, kelp and leafy stems.
- `description` / `descriptions`: one sentence about the theme for the themes window (the pack's, if it has none).

Anything a theme doesn't define comes from the app: no `background`, the usual one; no `looks`, the usual pieces;
no `sky`, the usual day.


## Scenery from packs
A pack can bring its own scenery: the drawing is a Metal function in the pack, the app places it, lights it, keeps
the fish, crabs and pearls clear of it and draws it with the rest of the scenery.

```json
"scenery": [
  { "id": "lantern", "name": "lanterna de pedra", "metal": "lantern.metal", "function": "draw_lantern",
    "anchor": "sand", "size": 0.08, "extent": [0.6, 1.0], "at": [0.3], "glowAtNight": true, "color": "#8a8a90" },
  { "id": "lilypad", "name": "vitória-régia", "metal": "lily.metal", "function": "draw_lily",
    "anchor": "surface", "size": 0.05, "extent": [1.0, 0.35], "count": 5 }
]
```

| Field | |
|---|---|
| `metal`, `function` | the file in the pack and the function in it (below) |
| `anchor` | `sand` (standing on the sand: the ground is at c.y ≈ -0.9), `surface` (floating, riding the waves: the water line is at c.y ≈ 0.12 / extent.y), `float` (in the water, at `height`) |
| `size` | its height, as a fraction of the tank's height (default 0.06) |
| `extent` | the quad's width and height, relative to `size` (default `[1, 1]`) |
| `at` | where the copies go, 0…1 from the left (one number or a list) |
| `count` | instead of `at`: how many copies (1…12), spread out from the id |
| `height` | 0…1 from the bottom, for `float` |
| `color` | `"#rrggbb"` or `[r, g, b]`: what the function gets as `col`, already lit by the hour |
| `glowAtNight` | `glow` rises as the light goes down, and its bright parts feed the bloom (a lantern's window) |
| `drift` | drifts slowly sideways (default: yes at the surface) |
| `solid` | the fish swim around it (default: yes, except at the surface) |

```metal
// c: -1…1 over the quad, y up. t: seconds. glow: 0…1. col: its color, lit.
// extra.y: a seed (different for each copy), extra.w: how dark the night is (0…1). Returns premultiplied rgba.
float4 draw_lantern(float2 c, float t, float glow, float4 col, float4 extra) { … }
```

The shader's helpers (`sd_box`, `sd_seg`, `sd_tri`, `smin_k`, `vnoise`, `hash21`, `vor_edge`) can be used. A theme
lists the pieces it wants in `"scenery"`, mixed with the built-in ones (`rock`, `shell`, `chest`, `coral`); a pack's
pieces only show up in a theme that lists them. A function that doesn't compile is dropped and reported in the menu,
like a fish.


## Creatures from packs
A pack can't bring code, so a creature from a pack is its drawing (a Metal function) plus one of the app's ready-made
behaviors, with parameters. Only themes that list it get it.

```json
"fauna": [
  { "id": "dragonfly", "name": "libélula", "metal": "dragonfly.metal", "function": "draw_dragonfly",
    "behavior": "skim", "size": 14, "count": [1, 2], "when": "day", "color": "#4fb0c0" },
  { "id": "frog", "name": "sapo", "metal": "frog.metal", "function": "draw_frog",
    "behavior": "perch", "on": "lilypad", "size": 16, "count": 2 }
]
```

| `behavior` | How it moves | Like |
|---|---|---|
| `cross` | swims across the tank now and then, at `height`, every `every` seconds | the turtle |
| `pass` | rare, far away in the background, faded by the water | the whale |
| `crawl` | walks on the sand (its feet at c.y ≈ -0.9), stops, turns around at the edges and the scenery | the crab |
| `rest` | stays on the sand, barely moving | the starfish |
| `glass` | climbs up and down the glass (its drawing's +x points the way it goes) | the snail |
| `drift` | floats, rising and sinking slowly, at `height` | a jellyfish |
| `school` | a little group wandering together | the decorative schools |
| `skim` | just under the surface (the water line at c.y ≈ 0.6), darting and stopping | — |
| `perch` | sits on a piece of scenery (`on`: its id; its feet at c.y ≈ -0.9), hopping to another copy now and then | — |
| `home` | lives around a piece of scenery (`on`: its id): swims about it, never far, pauses, goes back in | a clownfish in its anemone |

| Field | |
|---|---|
| `size` | in points, like the fish (default 16) |
| `extent` | the quad's width and height, relative to `size` (default `[1, 1]`) |
| `count` | how many (a number or `[min, max]`) |
| `speed` | points per second (default 20) |
| `height` | `[lo, hi]`, 0…1 from the bottom, for the ones that swim (default `[0.2, 0.7]`) |
| `every` | `[lo, hi]` seconds between visits, for `cross` and `pass` |
| `when` | `any`, `day` or `night` (it fades in and out with the light) |
| `shy` | swims away from the mouse |
| `front` | drawn in front of the fish (default: behind them) |
| `color` | `"#rrggbb"` or `[r, g, b]`: what the function gets as `col`, lit by the hour |

```metal
// c: -1…1 over the quad, y up, facing +x (the app mirrors it). phase: runs while it moves (legs, fins, wings).
// extra.y: a seed (different for each one), extra.w: 1 while it moves, 0 while it rests. Returns premultiplied rgba.
float4 draw_frog(float2 c, float phase, float glow, float4 col, float4 extra) { … }
```

An id that's already a built-in creature is refused; a function that doesn't compile is dropped and reported in the
menu.

## Presences from packs
New kinds of presence that plugins can use (`"kind": "floating-lantern"`), drawn by the pack and moved by the app
like the built-in ones:

```json
"presences": [
  { "id": "floating-lantern", "name": "lanterna flutuante", "metal": "floating.metal",
    "function": "draw_koi_floating_lantern", "motion": "float", "size": 26, "extent": [0.8, 1.0],
    "color": "#c8503c", "sound": "chime" }
]
```

| Field | |
|---|---|
| `motion` | `swim` (across, facing where it goes), `drift`, `hover`, `walk` (on the sand), `sit` (on the sand), `float` (at the surface) |
| `size`, `extent` | size in points, and the quad (width, height) relative to it |
| `band` | `[lo, hi]`, 0…1 from the bottom, where swimmers, drifters and hoverers stay |
| `meter` | shows `value` (0…1) in its drawing; the label adds the percentage |
| `drops` | drops from the surface when it arrives |
| `sound` | its voice when its state changes (one of the scene's voices, docs/scene.md) |

`float4 f(float2 c, float phase, float glow, float4 col, float4 extra)`: as a creature's, plus `extra.y` its value and
`extra.w` its state: 0 idle, 1 busy, 2 waiting, 3 ok, 4 alert, 5 error, 6 done, 7 born. `glow` rises with attention
(waiting, error). On the sand (`walk`, `sit`) the ground is at c.y ≈ -0.9. An id that's already a built-in kind is
refused.

