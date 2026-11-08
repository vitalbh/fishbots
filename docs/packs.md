# Making a pack

A pack is a folder with a `pack.json` and some `.metal` files. It can bring themes (water, light, seaweed, sand,
which creatures and scenery live there), music styles, fish, scenery and creatures. No Swift and no rebuilding: the
app reads the folder, compiles the drawings into its shader and shows them. `packs/examples/koi` and
`packs/examples/coral` are complete packs to learn from; `docs/extensions.md` has every field.

## 1. Start from the template

```sh
bin/fishbots pack new sunken-ship            # ./sunken-ship: a theme, a fish, a piece of scenery, a creature
bin/fishbots pack dev sunken-ship            # links it into the app; it reloads by itself on every save
```

Pick the pack's theme in the menu (Tema), and use its fish on a project through the fish's menu. From here, every
save shows up in the aquarium within a couple of seconds (or use **Tema → Recarregar pacotes**, or
`bin/fishbots pack reload`). A drawing that doesn't compile is left out and listed
at the bottom of the Tema menu; the rest keeps working.

## 2. Look at the drawings up close

```sh
bin/fishbots pack check sunken-ship          # validates pack.json and compiles each drawing: errors at file:line
                                             # (--catalog: also the catalog's metadata and cover; --offline: compiles
                                             #  with xcrun metal, for machines without a GPU like CI)
bin/fishbots pack preview sunken-ship        # sunken-ship/preview.png and preview-small.png
```

The preview draws a swatch of each theme (water, rays, seaweed, sand) and every drawing big, with its name: fish in
four patterns, asleep and glowing; scenery with two seeds and at night; creatures moving and resting.
`preview-small.png` shows them at about the size they have in the aquarium, enlarged 4× so the pixels show: **check
this one**, a detail that only reads big doesn't exist in the tank. `preview-motion.png` shows each drawing in six
moments, to see that what should move moves.

## 3. The drawing functions

Every drawing is a Metal function that gets a point `c` of its quad (-1…1, y up) and returns the color there,
premultiplied (`float4(rgb * a, a)`). Shape with distance functions, smooth the edge with `fwidth`:

```metal
float d = min(body, tail);                       // < 0 inside
float aa = fwidth(d) + 1e-4;
float a = 1.0 - smoothstep(-aa, aa, d);
return float4(color * a, a);
```

| | Signature | `c` | Notes |
|---|---|---|---|
| Fish | `(float2 c, float phase, float glow, float4 col, float4 extra)` | quad 1.25 × 0.8 of the size, facing +x | `phase`: the swim; `col`: the project's color; `extra.y`: pattern (0…7) + cut × 8; `extra.w`: fullness, + 2 asleep |
| Scenery | `(float2 c, float t, float glow, float4 col, float4 extra)` | `extent` × size; on the sand, c.y = -1 is the sand | `t`: seconds; `glow`: at night if `glowAtNight`; `extra.y`: seed per copy; `extra.w`: night |
| Creature | `(float2 c, float phase, float glow, float4 col, float4 extra)` | `extent` × size, facing +x | `phase`: runs while it moves; `extra.y`: seed; `extra.w`: 1 moving, 0 resting |

For square units, scale `c` by the quad's shape: `float2 p = c * float2(1.25, 0.8)` for a fish, `c * extent` (the
numbers in pack.json) for scenery and creatures.

Where the ground and the water are, in `c`: scenery on the sand and creatures that crawl, rest or perch stand at
**c.y ≈ -0.9** (end the shape there with a flat base and a little contact shadow: the strip below covers the sand);
scenery at the surface has the water line at **c.y ≈ 0.12 / extent.y**; creatures that skim, at **c.y ≈ 0.6**.

A glow outside the shape (a fish's `glow`, a lamp) goes where the shape isn't, fading before the quad's edge:

```metal
float edge = 1.0 - smoothstep(0.6, 1.0, max(abs(c.x), abs(c.y)));
float halo = glow * exp(-max(d, 0.0) * 12.0) * edge;
return float4(c3 * a + col.rgb * halo * (1.0 - a), a + halo * (1.0 - a) * 0.55);
```

Helpers from the app's shader you can call: `sd_box(p, half, radius)`, `sd_seg(p, a, b)`, `sd_tri(p, a, b, c)`,
`smin_k(a, b, k)` (smooth union), `vnoise(p)` (0…1), `hash21(p)` (0…1), `vor_edge(p)` (distance to the nearest
voronoi border: nets, plates, lace).

Rules that keep a pack working:
- Name functions after the pack (`draw_sunkenship_anchor`): every pack shares one shader, and two functions with the
  same name break both packs.
- Stay inside the quad: what goes past ±1 is cut off with a straight edge. Fade glows out before the edge.
- Several pieces can share one `.metal` file; it goes into the shader once.

## 4. Making it look good

What we learned redrawing the built-in fish and scenery:
- **Silhouette first.** At its real size a fish is 30–60 pixels. Shape it so it reads as itself in black: a tapered
  body, a tail stock, fins that stick out. Spots and scales come last.
- **Light from above.** Lighter on top, darker underneath (countershading), a thin rim of light along the top edge,
  a darker line under the belly. Flat colors look like stickers.
- **Round things are round.** Fake a normal from the shape (`float3(q, sqrt(1 - dot(q, q)))` on an ellipse) and light
  it; add a small highlight.
- **Fins and membranes are see-through:** alpha 0.8, lighter toward the edge, a few rays.
- **Texture breaks up the flat.** Two octaves of `vnoise` for patches, `vor_edge` for plates and nets, a little
  `hash21` speckle. Keep it subtle.
- **Glow is soft and wide,** and dies before the quad's edge; let `glow` drive it.
- **Movement sells it:** use `phase` for a wave along the body, a fluttering edge, stepping legs, a pulsing throat.

## 5. Share it

To put it in the community catalog (**Tema → Explorar pacotes…**), give `pack.json` its metadata (`version`,
`author`, `license`, `description`, and `names`/`descriptions` in other languages), make its cover with
`bin/fishbots pack cover sunken-ship`, check it with `bin/fishbots pack check sunken-ship --catalog` and send it as
a pull request: see [community/README.md](../community/README.md). Or share the file directly:

```sh
bin/fishbots pack zip sunken-ship            # sunken-ship.fishbotspack (it's checked first)
bin/fishbots pack install sunken-ship.fishbotspack       # or a https:// link, or double-click it in the Finder
```

A `.fishbotspack` is a zip of the folder. The app installs it only if it has a `pack.json` with a valid id and only
pack files (json, metal, md, txt, png), and puts it in `~/Library/Application Support/Fishbots/packs/<id>`.

## Safety

A pack is data and GPU drawing code: it can't run programs on the Mac, read your files, reach the network or see
your sessions. Its Metal runs on the GPU with only what the app gives it to draw. What a careless or hostile pack
*can* do is be expensive to draw (a slow aquarium, a warm Mac) or draw something misleading inside the tank; the
app's own windows (permissions, cards) are native and can't be drawn over.

The app watches the GPU time of every frame. If the aquarium gets slow (under 30 frames a second for a few seconds,
or much worse) while a pack's drawings are on screen, it hides them for a moment to check they are the cause, finds
which pack it is, and pauses it: it's left out until you turn it back on (Tema → Reativar), and a pack linked with
`pack dev` comes back by itself when you save a change. A frame the GPU has to abort pauses the packs on screen at once.

Installing a `.fishbotspack` checks it before anything is extracted: no links, no paths that climb out of the
folder (`../`, absolute), at most 20 MB, a `pack.json` with a valid id, only pack files (json, metal, md, txt, png).
Links are installed only from `https://`. Packs you link with `pack dev` are yours and aren't checked this way.

## For coding agents

`bin/fishbots skill install` puts a skill in `~/.claude/skills/fishbots-packs` that teaches an agent this whole
workflow: start from the template, preview, look at the sheet, fix, check the small sheet, zip.
