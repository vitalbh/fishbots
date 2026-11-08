# Fishbots pack reference

## A complete pack.json (the Japanese pond)

```json
{
  "id": "koi",
  "name": "Lago japonês",
  "themes": [
    {
      "id": "koi-pond",
      "name": "Lago japonês",
      "names": { "en": "Japanese pond" },
      "visualizer": "surface",
      "music": "zen",
      "fauna": ["snail", "turtle", "frog", "tadpoles", "shrimp"],
      "scenery": ["rock", "lantern", "lilypad"],
      "water": {
        "deep": "#0b2420", "shallow": "#3f7d62", "rays": "#cfe8b0", "raysStrength": 0.18,
        "caustics": "#e8f5c8", "causticsStrength": 0.07, "surface": "#7fb88f", "murk": "#2e3a1c"
      },
      "weeds": { "count": 7, "farCount": 10, "far": "#25463a", "low": "#1d4a2a", "high": "#7aa64a" },
      "sand": { "dark": "#3a3a34", "light": "#7a786a" }
    }
  ],
  "chords": {
    "Fm(add9)": [5, 8, 0, 7], "Dbmaj7": [1, 5, 8, 0], "Csus4": [0, 5, 7], "Bbm7": [10, 1, 5, 8]
  },
  "progressions": { "Pond": ["Fm(add9)", "Dbmaj7", "Bbm7", "Csus4"] },
  "styles": [
    {
      "id": "zen", "name": "zen", "bpm": [50, 60], "progressions": ["Pond"], "scale": [0, 1, 5, 7, 8],
      "lead": ["kalimba", "pluck", "flute"], "accomp": "arpeggio", "accompTimbre": ["pluck", "soft"],
      "notesPerBar": [1, 3], "swing": [0, 0.05], "keys": [0, 2, 5], "energy": 0.2, "rest": 0.5,
      "visualizer": "surface"
    }
  ],
  "fish": [
    { "id": "koi", "name": "carpa koi", "metal": "koi.metal", "function": "draw_koi" }
  ],
  "scenery": [
    { "id": "lantern", "name": "lanterna de pedra", "metal": "lantern.metal", "function": "draw_lantern",
      "anchor": "sand", "size": 0.11, "extent": [0.6, 1.0], "at": [0.27], "glowAtNight": true, "color": "#8c8c88" },
    { "id": "lilypad", "name": "vitória-régia", "metal": "lily.metal", "function": "draw_lily",
      "anchor": "surface", "size": 0.06, "extent": [1.0, 0.7], "at": [0.12, 0.3, 0.52, 0.71, 0.88], "color": "#4f8a3e" }
  ],
  "fauna": [
    { "id": "frog", "name": "sapo", "metal": "creatures.metal", "function": "draw_frog",
      "behavior": "perch", "on": "lilypad", "size": 15, "extent": [1.2, 1.0], "count": 2, "color": "#5f8f3e" },
    { "id": "tadpoles", "name": "girinos", "metal": "creatures.metal", "function": "draw_tadpole",
      "behavior": "school", "size": 7, "extent": [2.0, 1.0], "count": [6, 9], "speed": 18, "height": [0.15, 0.45],
      "color": "#3a3328", "shy": true },
    { "id": "shrimp", "name": "camarão", "metal": "creatures.metal", "function": "draw_shrimp",
      "behavior": "crawl", "size": 10, "extent": [1.6, 1.0], "count": [2, 3], "speed": 8, "color": "#d9806a" }
  ]
}
```

Fish entries: `{"id", "name", "metal", "function"}`.

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

