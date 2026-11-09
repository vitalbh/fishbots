---
name: fishbots-packs
description: Make, fix or polish a Fishbots pack — a folder with pack.json and Metal drawings that adds themes, music styles, fish, scenery and creatures to the Fishbots aquarium app. Use when the user asks for a new aquarium theme, a new kind of fish, a creature or a piece of scenery for Fishbots, or to package/share/install a pack.
---

# Making Fishbots packs

A pack is a folder: `pack.json` plus `.metal` files. Each drawing is a Metal function the app compiles into its
shader; how things move and where they sit comes from the app (you only pick and tune). No Swift, no rebuild.
Field reference: `reference.md` next to this file.

## Find the tools

The `fishbots` CLI does everything (`fishbots pack …`). It lives in the Fishbots repository at `bin/fishbots`; try
`command -v fishbots`, then the repository's `bin/fishbots`. It needs the app built (`scripts/app.sh`) or installed;
`FISHBOTS_APP=/path/to/Fishbots` points it at a binary. `check`, `preview`, `new` and `zip` work with the app closed;
`dev`, `install`, `list` and `reload` talk to the running app.

## The loop

1. **Start from the template:** `fishbots pack new <id> <folder>` (id: lowercase, digits, `-`, `_`). You get a theme,
   a fish, a piece of scenery and a creature that compile. Rename, delete or add pieces in `pack.json`.
2. **Link it while you work** (only if the user's app is open and they want to watch): `fishbots pack dev <folder>`.
   The running aquarium reloads it on every save. Without the app, the preview below is enough; it shows the theme
   too (a swatch), but not the music.
3. **Draw, then look:** after every change run `fishbots pack preview <folder>` and **read the images** with your
   image-viewing tool. Judge the drawing from the images, never from the code. Iterate until they look right.
   - `preview.png`: big and labeled. A swatch of each theme (water, rays, seaweed, sand), fish in 4 patterns +
     asleep + glowing, scenery with two seeds and at night, creatures moving and resting.
   - `preview-small.png`: the drawings at their real size, enlarged 4×. If it doesn't read here, it doesn't read.
   - `preview-motion.png`: each drawing in six moments (fish and creatures by phase 0…3, scenery by time 0…6 s).
     Check that what should move moves, and that nothing jumps or pops.
4. **Errors:** `fishbots pack check <folder>` prints Metal errors as `file.metal:line:col` in the pack's own files.
   Fix the first error first (later ones often follow from it). A piece that doesn't compile is left out of the
   aquarium and listed at the bottom of its Tema menu; the rest keeps working.
5. **For the community catalog:** fill in `version` (1.0), `author`, `license` (MIT, CC-BY-4.0…), `description`,
   and `names`/`descriptions` with `{"en": "…"}` (on the pack and on each theme, fish, scenery, creature and style:
   the app shows them in its language). Then `fishbots pack cover <folder>` (cover.png) and
   `fishbots pack check <folder> --catalog`. Submitting is a pull request adding the folder to `community/packs/`
   in the Fishbots repository and running `python3 scripts/catalog.py` (see `community/README.md` there).
6. **Share:** `fishbots pack zip <folder>` → `<id>.fishbotspack` next to the folder (checked first). Install with
   `fishbots pack install <file|https url>` (the app must be open; only https links) or a double-click in the Finder.

Don't touch the user's real aquarium settings (theme, fish kinds) unless asked; tell them which theme to pick.

## Drawing contract

Every function returns **premultiplied** color: `float4(rgb * a, a)`. `c` is the point in the quad, -1…1, **y up**.
Shape with signed distances (negative inside) and antialias with `fwidth`:

```metal
float d = min(body, tail);
float aa = fwidth(d) + 1e-4;
float a = 1.0 - smoothstep(-aa, aa, d);
return float4(color * a, a);
```

- **Fish** `float4 f(float2 c, float phase, float glow, float4 col, float4 extra)`: quad is 1.25 × 0.8 of the size;
  use `float2 p = c * float2(1.25, 0.8)` for square units. Faces +x (the app mirrors it). `phase` = swim cycle;
  `col.rgb` = the project's color, `col.a` = opacity (multiply it in); `extra.y` = pattern (0…7) + cut × 8 (offer
  variety by `int(extra.y + 0.5) % 4`); `extra.w` = fullness 0…1, + 2 while asleep (close the eye); `glow` 0…1:
  add `col.rgb * glow * 0.45` and an outer halo.
- **Scenery** `float4 f(float2 c, float t, float glow, float4 col, float4 extra)`: quad = `extent` × size; use
  `float2 p = c * extent` (the numbers from pack.json, e.g. `c * float2(0.6, 1.0)`) for square units. `t` seconds;
  `glow` rises at night when `glowAtNight`; `extra.y` seed per copy (vary shape, tilt and wear with it visibly);
  `extra.w` night 0…1.
- **Creature** `float4 f(float2 c, float phase, float glow, float4 col, float4 extra)`: quad = `extent` × size, faces
  +x; `float2 p = c * extent` for square units. `phase` runs while it moves; `extra.w` 1 moving / 0 resting (legs
  step, wings flap only when moving); `extra.y` seed. Movement comes from `behavior`: cross, pass, crawl, rest,
  glass, drift, school, skim, perch, home.

**Where the ground and the water are**, in `c`:
- Scenery on the `sand` and creatures that `crawl`, `rest` or `perch`: the ground is at **c.y ≈ -0.9**. Put the
  base or the feet there. The strip below covers the sand, so end the shape with a flat base and darken it near the
  ground (a contact shadow). `perch` stands on top of the piece named in `on`.
- Scenery at the `surface`: the water line is at **c.y ≈ 0.12 / extent.y**. Above it is air (a flower, a frog);
  below it hangs in the water (stems, roots).
- Creatures that `skim`: the water line is at **c.y ≈ 0.6**; the body hangs below it.
- Anything else (`float` scenery, swimmers) is free in the water.

**A glow or halo outside the shape** (fish when `glow` > 0, a lamp): add it where the shape isn't, fading before the
quad's edge, and give it a little alpha so it shows over the water:
```metal
float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
float halo = glow * exp(-max(d, 0.0) * 12.0) * edge;          // d: the shape's distance
return float4(c3 * a + col.rgb * halo * (1.0 - a), a + halo * (1.0 - a) * 0.55);
```

Helpers you can call: `sd_box(p, half, r)`, `sd_seg(p, a, b)`, `sd_tri(p, a, b, c)`, `smin_k(a, b, k)` (smooth union),
`vnoise(p)` 0…1, `hash21(p)` 0…1, `vor_edge(p)` (distance to voronoi borders: plates, nets, lace).

**Pitfalls that break the shader for everyone:**
- Function names must be unique across all packs: prefix with the pack id (`draw_reef2_anchor`), and the same for
  any helper you define (`reef2_wave`). Never redefine the app's helpers.
- No globals except `constant` ones; no `half` as a variable name; define a helper above the function using it.
- Several pieces may share one `.metal` file (it goes into the shader once).
- Anything past ±1 is clipped with a straight edge: keep shapes inside, and fade glows to zero before the edge.
- **There's plenty of room — don't skimp on looks, just avoid brute force.** A whole aquarium with the Japanese
  pond's koi, lantern, lily pads, frogs, tadpoles and shrimp draws in about 10 ms a frame; the app only steps in past
  33 ms. Detailed drawings like the koi (scales, two-octave patches, lighting, rayed fins) or the octopus (6 arms × 8
  segments) are fine. What's too much: loops of hundreds of steps per pixel, dozens of `vor_edge` calls, ray
  marching. Early `return float4(0.0)` where the shape isn't is a free win. If a drawing does go too far, the app
  pauses its pack (Tema → Reativar; a `pack dev` pack comes back on the next save), so it simply disappears.

## Making it look good (the house style)

The built-in aquarium is soft, rounded, lit from the surface, and reads at 30–60 px. Match it:
- **Silhouette first.** Check `preview-small.png`: the thing must read as itself there. Tapered bodies, a narrow
  tail stock, fins that stick out, a clear head. Details that vanish small are decoration, not identity.
- **Lit from above:** lighter top, darker belly (countershading), a thin bright rim along the top edge, a darker
  line along the bottom edge. Never flat fills.
- **Volume:** fake a normal on round parts, `float3 n = normalize(float3(q, sqrt(max(0.02, 1.0 - dot(q, q)))))`
  with `q` the point divided by the radii, and light it with `dot(n, normalize(float3(-0.3, 0.8, 0.5)))`; add a small
  specular highlight.
- **Membranes** (fins, petals, leaves) see-through (alpha ≈ 0.8), lighter toward the edge, with rays or veins.
- **Texture** with restraint: two octaves of `vnoise` for patches and moss, `vor_edge` for plates/scales/nets, a few
  `hash21` speckles. Mix at 20–50 %, not 100 %.
- **Glow** is a small bright core inside a wide soft falloff (`exp(-r*r*k)` with two or three k's), driven by `glow`.
- **Motion:** a wave along a body (`p.y -= sin(phase - p.x * 2.5) * amp * tailward`), fluttering edges, stepping
  legs, a pulsing throat. Subtle and continuous.
- Colors come from `col` (the project or the pack's color); derive shades from it so every color works.

## Backgrounds, looks, presences and sounds

- **Theme background:** `"background": {"metal", "function", "replaceReef": true}` on a theme; the function is
  `float4 f(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra)` (uv 0…1 over the window, y up;
  mix toward `water` for distance haze; `extra.x` aspect, `extra.z` the sand line's height). It covers the whole
  window: keep it cheap (skip pixels early, e.g. `if (uv.y > 0.6) return float4(0.0);`).
- **Looks:** `"looks"` on a theme dresses built-in things by id, keeping what they mean: a piece (`rock shell chest
  coral`) → one of the pack's scenery ids (a chest gets how open it is in `extra.y` and glows while open); a presence
  kind (`"bottle": "floating-lantern"`) → one of the pack's presences that moves the same way (checked), or a built-in variant (`"shark": "hammerhead"`,
  `"helm": "rusty-helm"`, `"bottle": "deep-bottle"`, `"chest": "safe"`); a fish kind
  (`"oval": "koi"`; `"betta"` is the music fish, `"lanternfish"` the night one) → one of the pack's fish (a kind picked
  by hand stays); a built-in creature (`crab turtle snail starfish whale jellyfish`) → one of the pack's creatures.
  Users can turn dressing off.
- **Sand and seaweed:** `"looks"` also takes `pebble`, `seashell` and `pearl` (→ pack scenery: river stones, ice chips;
  a pearl gets the project's color); `"weeds": {"shapes": ["reed", "ribbon", "blade", "kelp", "leafy"]}` picks the
  seaweed's shapes.
- **Ambience:** `"looks"` takes `mote` (marine snow: petals, ice crystals), `bubble`, `food` too; `"foreground": false`
  removes the blurred tufts up front; `"voices": {"chime": "koto"}` gives the scene's sounds another voice or a pack sound.
- **Schools and jellyfish:** `"schools": [{"color", "kind", "count", "size": [lo, hi], "pattern", "depth": [lo, hi]}]`
  (up to 3: middle, high, low and far) replaces the tropical neons; `"jellyfish": false` removes the drifting one.
- **Frost:** `"frost": 0.6` (0…1) grows ice on the glass from the sides and corners.
- **Presences** (`"presences"`): kinds plugins can send (`"kind": "<id>"`), with `motion` (swim drift hover walk sit
  float), `size`, `extent`, `band`, `meter`, `sound`. Function like a creature's; `extra.y` is the value (0…1) and
  `extra.w` the state (0 idle, 1 busy, 2 waiting, 3 ok, 4 alert, 5 error, 6 done, 7 born): show it (color, light,
  motion). The preview draws them as ok, busy, error and waiting.
- **Sounds** (`"sounds"`): `{"id", "file": "x.wav", "root": "A3", "gain"}`, a short recorded note (wav/aiff/caf, ≤ 12 s)
  used by id in a style's `lead` / `accompTimbre`. You can't hear the result: say so, and describe what you made.

Anything left out comes from the app (the usual background, pieces, presences and timbres).

## Themes and music (no drawing)

A **theme** in `pack.json`:
- `water`: `deep` (bottom), `shallow` (top), `rays` + `raysStrength` (0…1, sunbeams), `caustics` +
  `causticsStrength` (0…0.2, light patterns), `surface` (the water line), `murk` (the color of murky water).
- `weeds`: `count` (0…16 blades in front), `farCount` (blades far behind), `far`, `low` (base color), `high` (tip
  color). `sand`: `dark`, `light`.
- `fauna`: built-ins `crab starfish turtle snail lanternfish whale grouper anglerfish sunfish` and the pack's creature ids.
  `scenery`: built-ins `rock shell chest coral` and the pack's scenery ids. Leave a list out for all built-ins.
- `visualizer`: `plankton`, `aurora`, `surface`, `score`, `constellation` or `fireworks`. `music`: a style id.
- `names`: `{"en": "…"}`, the name in other languages. Colors are `"#rrggbb"` or `[r, g, b]` (0…1).

A **music style** (`styles`): `bpm` [lo, hi]; `progressions`: built-ins `Pop Melancholic Dreamy Jazzy Nostalgic
Open Bossa` or the pack's own (`"progressions": {"Pond": ["Fm(add9)", "Dbmaj7"]}`, chords from the built-ins `C
Cmaj7 Dm7 Em7 F Fmaj7 Fm G G7 Gsus4 Am Am7 Bb A7` or the pack's `"chords": {"Dbmaj7": [1, 5, 8, 0]}`, pitch classes
from C); `scale`: `"major"`, `"penta"` or pitch classes (`[0, 1, 5, 7, 8]`); `keys`: the keys it may be played in
(pitch classes); `lead` and `accompTimbre` from `pluck bell pad bass glass bubble soft rhodes flute kalimba tap`;
`accomp`: `arpeggio`, `lofi` or `bossa`; `notesPerBar` [lo, hi] (1…4); `swing` [lo, hi] (0…0.3); `energy` 0 calm…1
busy; `rest` 0…0.9, the chance a phrase stays silent; `barsPerChord` (default 2). See `reference.md` for a complete
pack.json.

## Done means

`fishbots pack check` passes; you looked at `preview.png` and `preview-small.png` and they look like the aquarium's
style; the theme was seen in the app (`fishbots pack dev`, then pick it) if the app is available; the user knows the
theme's name and how to install or share the pack.
