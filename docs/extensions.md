# Extension points (design)

Status: the order of work below is implemented (v0.4). Goal: every part people will want more of (themes, session providers,
visualizers, fish…) gets a clear seam, so that it can grow from two places without touching the core:

1. **Built-ins** in this repository (Apache 2.0): Claude Code, Codex, the current visualizers and the tank as it is.
2. **Packs**: folders of data (JSON, plus Metal for fish) that anyone can drop in, with no compiling.

## Two layers

- **Registries in Swift.** Each extension point is a protocol plus a registry (`Registry<Visualizer>`, …). The core only
  talks to the protocol; built-ins call `register(...)` at launch. No dynamic loading of compiled
  code: dylib plugins clash with code signing and the hardened runtime, and xbar-style script plugins already cover
  "run my own code" for sources.
- **Packs on disk.** `~/Library/Application Support/Fishbots/packs/<id>/pack.json` declares themes, music styles,
  fish, scenery and creatures (each drawing a `.metal` file). Packs are data and GPU code only:
  they can't run anything on the Mac. Everything is validated on load; a broken piece is skipped and reported in the
  menu, and a pack that slows the aquarium down is paused. How to make one: [packs.md](packs.md); the community
  catalog: [../community/README.md](../community/README.md).

## The extension points

### 1. Session providers
Today the knowledge about each agent is spread out: `ClaudeCodeHook` (events → state), `Transcript` (title, branch,
context, last reply; one branch for Claude, one for Codex), `Whereabouts` (go to the terminal, type a reply, Esc,
rename), `Permissions`, plus `if source == "codex"` checks here and there.

```swift
protocol SessionProvider {
    var id: String { get }                                   // "claude-code", "codex", "gemini-cli"…
    var routes: [String] { get }                             // e.g. "/claude-code", "/codex"
    func handle(_ body: Data, headers: [String: String], tank: Tank) -> (Int, Data)
    func details(for fish: Fish) async -> SessionDetails     // title, branch, context, last reply, question
    var capabilities: Set<Capability> { get }                // .reply, .stop, .rename, .permissions, .goTo
    func reply(_ text: String, to fish: Fish) async throws
    func stop(_ fish: Fish) async throws
    func rename(_ fish: Fish, to name: String) async throws
    func defaultFish(for fish: Fish) -> FishKind.ID          // which fish this session becomes
}
```

The card, the fish menu and the music only ask the fish's provider what it can do (no "Responder" without `.reply`).

**Agents without Swift** (`AgentManifests.swift`): an agent whose hook or plugin posts Claude Code-shaped events to
`POST /agent/<id>` becomes a full agent fish (tool animations, fry, the card and its last reply, where it runs,
reply/Esc in the exact terminal). A manifest is optional (`~/Library/Application Support/Fishbots/agents/<id>.json`,
read when the app opens and reloaded from Preferences → Agents or `POST /agents/reload`; it travels with the agent's
hook, not in packs, which are only the look):
`name`, `processNames`, `fish` (any kind id, a pack's too), `timbre`, and `events`/`tools` maps from the agent's
names to Claude Code's. Without one, `<id>` is the process name and the fish follows the terminal. Built-in ids
can't be taken. The translation lives in the agent's hook (any language): opencode's plugin
(`plugins/opencode/fishbots.js`) is the reference. How to connect one: [agents.md](agents.md); the
`fishbots-agents` skill teaches a coding agent to do it. What still needs Swift: reading the agent's own conversation files
(title, context, branch), renaming conversations, and answering permissions.

**Adding a built-in agent** (as implemented in `Providers.swift`):
1. `plugins/<agent>/hook.sh`: a one-liner that runs `plugins/common/hook.sh <route> '<glob of its executable>'…`
   (forwards stdin and the `X-Where-*` headers; `FISHBOTS_HOOK_LOG=1` keeps the last event to study the format), plus
   the agent's own hook config (`hooks.json`). Permissions, if its hook format matches Claude Code's:
   `plugins/common/permission.sh <route>`.
2. A provider registered in `Providers.registerBuiltIns()`: `id`, `routes`, `profile` (timbre, fish kind) and
   `processNames` (words in its process path, used to check the Rex pane before typing and whether a saved session is
   still alive). Subclass `TerminalAgentProvider` to get reply/stop through Rex, Herdr, Ghostty, iTerm and tmux.
3. Translate its events: if the JSON looks like Claude Code's (`session_id`, `hook_event_name`, `tool_name`, `cwd`,
   `transcript_path`), call `ClaudeCodeHook.apply`; otherwise rename its fields/events in `handle` first.
4. Optional: a branch in `Transcript` for title, branch, context and last reply.
Script plugins and `POST /event` become one more provider ("generic") with no capabilities beyond going to a link.

### 2. Fish kinds
Today: `Fish.species` (0–5) is decided by an `if` chain on the source and terminal, and the shader picks the drawing
with another `if` chain (`draw_fish`, `draw_octo`, `draw_ray`).

```swift
struct FishKind {
    let id: String              // "oval", "octopus", "koi"…
    let call: String            // the Metal call: a pack's float4 draw_<id>(float2 c, float phase, float glow, float4 col, float4 extra)
    var swim: FishSwim          // the quad (extent), speed, depth band, beat, bob, upright (a pack fish's "swim", docs/packs.md)
}
```

Since the shader is already compiled when the app opens (`makeLibrary(source:)`), the app concatenates the built-in
shader, every registered `draw_<id>` and a generated `switch` on the kind index. Packs bring new fish as `.metal`
files. Which fish a session gets: the provider's default, overridable per project in the fish menu (next to "Trocar
motivo").

### 3. Visualizers
Today: `VisualMode` (enum) plus `switch mode` inside `Visual.note`, `chord`, `event` and `sprites`.

```swift
protocol Visualizer {
    var id: String { get }
    var title: String { get }                 // shown in the menu
    func note(at: SIMD2<Float>?, pitch: Float, vel: Float, color: SIMD3<Float>, key: String, in: VisualContext)
    func chord(_ pcs: [Int], in: VisualContext)
    func event(at: SIMD2<Float>, in: VisualContext)
    func update(dt: Float, energy: Float, in: VisualContext)
    func sprites(in: VisualContext) -> [Sprite]
}
```

`VisualContext` holds the shared particle pool and helpers (spark, line, ring, ripple), so a visualizer is mostly
rules on top of existing sprite kinds. The automatic choice by music style moves into the style (`visualizer: "score"`).
The aurora background stays a core feature that visualizers draw on top of.

### 4. Themes (scenes)
Today the scene is constants: water gradient (`deep`, `shallow`) and fog in the shader, sand and weeds in `Tank`,
which creatures exist in `Fauna`, the daylight curve.

A theme is data, passed to the shader as uniforms (no recompiling):

```json
{ "id": "reef", "name": "Recife",
  "water": { "deep": "#031229", "shallow": "#0d4d66", "fog": 0.35, "caustics": 0.8 },
  "sand": { "color": "#c8b48a", "height": 0.075 },
  "weeds": { "count": 12, "colors": ["#2f6b3a", "#4f8a3c"] },
  "fauna": ["crab", "turtle", "snail", "whale"],
  "music": "ambient", "visualizer": "constellation" }
```

Ideas for packs: coral reef, deep sea (dark, bioluminescent), Japanese pond (koi), night aquarium. Two are in
`packs/examples/`: `coral` (a reef: clownfish, anemones, chromis, a blue tang, the reef wall, marimba), `koi` (a Japanese
pond: koi, a stone lantern, lily pads, a shrine for the chest, frogs, koinobori, a water wheel, the namazu, koto) and
`arctic` (under the ice: an ice ceiling, polar cod, a seal, a narwhal, the frozen chest, its own cold sky) and `kelp`
(a kelp forest: giant kelp to the surface, an urchin barren, the sheephead, garibaldi, a sea otter, sea lions) and
`trench` (an abyssal trench: no daylight, black smokers, tube worms, a whale fall, comb jellies, a siphonophore, a
bathysphere for the chest, session fish as lanternfish lit in the project's color) and `amazon` (the Amazon's
blackwater: the flooded forest behind tea-colored water, giant water lilies, a sunken branch, a Marajoara urn for the
chest, session fish as discus, piranhas and peacock bass, cardinal tetras, an arapaima, the pink river dolphin, a river
stingray, a pleco on the glass, an electric eel, a black caiman for the shark) and `ocean` (the open sea: no floor, shafts of light fanning down, session fish as shark pups, sardines in schools, the dorado, tuna, a whale shark far away, flying fish, moon jellies, sargassum adrift with the clutch of eggs hanging in it) and `desk` (a little tank on a desk: blue gravel, a plastic castle and plastic plants, a toy diver, a no-fishing sign, goldfish, the bubble-eye, guppies, a pleco on the glass, and behind the glass the room out of focus, where a cat comes to look in).

#### A theme's own background and looks
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
- `leader`: the fish kind (built-in or the pack's own) a session is drawn as while it leads a school of sessions it
  launched (`"leader": "lanternfish"`). Without it, the nautilus. It keeps that shape until its session ends.
- `looks`: how the theme dresses built-in things, by id. The meaning stays, only the drawing changes:
  - a **piece of scenery** (`rock`, `shell`, `chest`, `coral`) drawn by one of the pack's scenery pieces, in the same
    place and with the same behavior (the chest still opens the summary). A chest's drawing gets how open it is in
    `extra.y` (instead of the seed) and glows while it's open. The piece doesn't need to be in the theme's `scenery`;
  - a **presence kind** plugins send (`"bottle": "floating-lantern"`): drawn as one of the pack's presences that moves
    the same way (checked on load), keeping its label, state, link and sound. A plugin that wants its own drawing
    sends `"override_theme": true`;
    The app's own variants work too: `"shark": "hammerhead"`, `"helm": "rusty-helm"`, `"eggs": "egg-case"` (the deep sea's clutch: a shark's egg case) or `"root-eggs"` (the
    lagoon's: eggs along a mangrove root), `"bottle": "deep-bottle"`
    (the deep sea's barnacle-crusted bottle, plankton glowing in the state's color), `"chest": "safe"` (a ship's
    safe) and `"chest": "fish-trap"` (a woven fishermen's trap), for the chest piece and the chest presence. Built-in
    scenery only for themes that list it: `helmet` (an old diving helmet on the sand), `wreck` (a sunken ship far away)
    and `mangrove` (prop roots coming down at the sides). Built-in creatures for a theme's `fauna`: `anglerfish`,
    `sunfish`, `manatee`, `seahorses`, `pufferling` (a little puffer that blows up when the mouse comes near), `gulper` (a gulper eel, a rare visitor), `seasparkle` (plankton that lights up at night behind whoever swims fast).
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
- `effects`: the effects plugins ask for, the theme's way: a default color (`{"fireworks": "#ff9ec8"}`), or another
  effect in its place (`{"lightning": {"as": "sparkle", "color": "#a0ffd0"}}`). A color the plugin sends still wins.
  The quake's dust takes the theme's sand.
- `swim`: how fish swim here, on top of each kind's own way: `{"*": {"speed": 0.8, "beat": 0.85}, "puffer": {"bob": 0.2}}`.
  `"*"` is every kind (built-in ones too), a kind's id just that kind. `speed` and `beat` multiply; `depth`, `bob` and
  `upright` replace. The quad (`extent`) stays the kind's.
- `voices`: the scene's voices (what presences and effects sound like, docs/scene.md) given another voice or one of the
  packs' recorded sounds: `{"chime": "koto", "kalimba": "marimba"}`. The crossing school effect uses the theme's first
  school.
- `foreground`: `false` leaves out the blurred seaweed tufts up front; a color tints them.
- `weeds.shapes`: the seaweed's shapes, mixed along the tank: `blade`, `kelp`, `leafy`, `reed` (straight, some with a
  cattail's head), `ribbon` (thin, dark, waving). Without it, blades, kelp and leafy stems.
- `description` / `descriptions`: one sentence about the theme for the themes window (the pack's, if it has none).

Anything a theme doesn't define comes from the app: no `background`, the usual one; no `looks`, the usual pieces;
no `sky`, the usual day.

#### Scenery from packs
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
| `bury` | on the sand: how much of the quad's height sits below the sand line (default 0.05). A wide piece needs more (0.3), and should fade out below that line, so it doesn't float where the tank's sand dips |

```metal
// c: -1…1 over the quad, y up. t: seconds. glow: 0…1. col: its color, lit.
// extra.y: a seed (different for each copy), extra.w: how dark the night is (0…1). Returns premultiplied rgba.
float4 draw_lantern(float2 c, float t, float glow, float4 col, float4 extra) { … }
```

The shader's helpers (`sd_box`, `sd_seg`, `sd_tri`, `smin_k`, `vnoise`, `hash21`, `vor_edge`, and for fish `fish_round` and `fish_eye`: docs/packs.md) can be used. A theme
lists the pieces it wants in `"scenery"`, mixed with the built-in ones (`rock`, `shell`, `chest`, `coral`; the clutch of `eggs`, where the
sessions started from the aquarium hatch and a click starts one, is in every theme, unless the theme lists a pack
piece of its own called `eggs`, which then is its clutch: the open sea hangs it in the sargassum; the same goes for a pack piece called `chest`, which is
then the theme's chest wherever the pack anchors it, lid and summary included; only in that pack's own themes). A theme with `"floor": false` has no floor to lay things on (the open sea): no pearls of the day
(they're kept, and come back with a theme that has one), no sand, no pebbles and shells, no list pebbles, no old battery, no bubbler, no shadows under the fish; its
background should take the water down to the bottom of the window. A theme with `"surface": false` has no water's
surface (a sky, the constellations): no water line, no sky band over it, no sun or moon seen through it, no glints, no rings
where bubbles reach the top; its background paints the whole window (set `raysStrength` and `causticsStrength` to 0 too).
Two packs can each have their own `eggs` and `chest`; a pack's
pieces only show up in a theme that lists them. A function that doesn't compile is dropped and reported in the menu,
like a fish.

### 5. Tool behaviors
Today a hard-coded `switch` maps tool names to an action (nibble, bubbles, forage, peek, mail), a label icon and a
timbre. It becomes a table that providers extend (`"Bash": .bubbles`, `"mcp__*": .mail`, and e.g. "the agent runs the
tests" → a new action), with glob patterns for tool names.

### 6. Music styles and timbres
`Style` is data: packs add styles (bpm range, scale, progressions, rhythm, voices). The synthesized timbres stay in
Swift (`Synth.render` is real-time audio code), but a pack can bring **recorded sounds** that become timbres:

```json
"sounds": [ { "id": "koto", "name": "koto", "file": "koto.wav", "root": "A3", "gain": 0.9 } ]
```

`file` is a wav, aiff or caf in the pack (mixed down to mono, at most 12 s); `root` is the pitch it was recorded at (a
note name or a MIDI number); the note is resampled to each pitch. Styles use it by id in `lead` and `accompTimbre`,
next to the built-in timbres. Up to 16 sounds in all packs together.

### 7. Fauna
Each creature (crab, turtle, whale, snail, lanternfish) is a `Creature` with `update`, sprites per layer
(background, middle, front) and a rule for when it shows up. A theme lists which creatures it uses.

A creature that carries a light says so in `lamps(_:)` (where, how far it reaches, its color and strength): the
strongest four go to the shader (`lamp_light`), and the seaweed, the sand and the marine snow around them take the
light. The lanternfish and the anglerfish do.

#### Creatures from packs
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
| `crawl` | walks on the sand (its feet at c.y ≈ -0.9), stops, turns around at the edges; it keeps to the bare sand up front, so it passes in front of the scenery, never over it | the crab |
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

#### Presences from packs
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
| `motion` | `swim` (across, facing where it goes), `drift`, `hover`, `walk` (on the sand), `sit` (on the sand), `float` (at the surface), `glass` (a small light on the side glass, with the others from its source; drawn facing the middle of the tank: the glass is behind c.x = 0, and its color is the state's) |
| `size`, `extent` | size in points, and the quad (width, height) relative to it |
| `band` | `[lo, hi]`, 0…1 from the bottom, where swimmers, drifters and hoverers stay |
| `meter` | shows `value` (0…1) in its drawing; the label adds the percentage |
| `drops` | drops from the surface when it arrives |
| `sound` | its voice when its state changes (one of the scene's voices, docs/scene.md) |

`float4 f(float2 c, float phase, float glow, float4 col, float4 extra)`: as a creature's, plus `extra.y` its value and
`extra.w` its state: 0 idle, 1 busy, 2 waiting, 3 ok, 4 alert, 5 error, 6 done, 7 born. `glow` rises with attention
(waiting, error). On the sand (`walk`, `sit`) the ground is at c.y ≈ -0.9. An id that's already a built-in kind is
refused.

### 8. Outputs (sinks)
The opposite of providers: `EventSink` receives what happens in the tank (state changes, done, error, permission
requests) and sends it somewhere: a webhook, Slack, Home Assistant, a desk light.

### 9. Fish menu actions
Providers and plugins can add actions to the fish menu and the card ("Abrir o PR", "Rodar os testes de novo", "Abrir
no editor"), each with a condition (`when: fish.link != nil`).

### 10. Interface languages
Not a code extension point but the same idea: the on-screen text moves into string tables (pt, en…), and packs can
bring translations.

### 11. Session control and launchers
Status: implemented (`SessionControl.swift`, `Launchers.swift`), with launchers for Rex, Herdr, iTerm, tmux and the
background; each has run a whole cycle (spawn, wait, reply, stop, close) with real sessions (iTerm's with Claude
Code and a fake agent; the others with Claude Code and Codex).

The aquarium already sees every agent in every client and can type into most of them. Letting a session use that
makes it an orchestrator: **the orchestrator is not a feature of the app, it's an ordinary agent session** that
calls the aquarium. The app runs no model and holds no API key; it stays the bus and the window. Any agent can lead,
and the leader is a fish like the others (card, timeline, permissions).

**Control routes** (`POST /control/…`, off until "Sessões podem comandar outras" is on in Preferences; the same
checks as the card apply, so nothing is typed where the card wouldn't type):

| Route | Body | Answer |
|---|---|---|
| `/control/reply` | `fish`, `text` | ok, or why not (not at its prompt, another program in front…; or it was told to be asking something and someone answered that meanwhile: refused once, so an answer doesn't land as a new message) |
| `/control/stop` | `fish` | ok |
| `/control/close` | `fish` | closes the pane of a session the asker launched (the launcher's `close`); its fish leaves |
| `/control/wait` | `fish` (one or many), `states`, `timeout` | held until one of them stops working (done, waiting, error, idle; or the `states` asked for): which, its state, its last reply, what it asks (`asked`, `permission`). A question already told isn't told again: the next `wait` is for what comes after it |
| `/control/spawn` | `agent`, `model`, `cwd` (`worktree`, `branch`: echoed back; the CLI's `--worktree` makes them), `prompt`, `label`, `launcher`, `tab`, `env` | held until the fish is born: `fish`, `state`, `parent`, `where` |

**Token** (`ControlTokens.swift`): every control route needs `Authorization: Bearer <token>` and answers 401
without one of this run's. The reading routes (`/state`, `/packs`…) and the hooks' (`/claude-code`, `/agent/<id>`,
`/event`…) take none. All tokens are new on every launch and none is kept:

- **The person's:** 32 random bytes the app writes as hex to `control.token` in its Application Support folder, next to
  `fish.json` (0600; `control-<port>.token` for an aquarium on another port, so a test instance doesn't overwrite it).
  Full reach. `fishbots` reads it from any terminal, and the resident assistant's brain gets it in its environment.
  With it, the asker is the session the `X-Where-*` headers point at (as below), so the guards stay what they were.
- **A session's own:** each session the aquarium launches (`spawn`, the menu) gets one in its pane's environment
  (`FISHBOTS_TOKEN`), tied to the pane it was launched in and so to the fish born there. With it the asker is that
  fish, whatever the headers say, and `reply`, `stop` and `close` reach only the sessions launched with a token it
  passed on (known by the tokens the app gave out, not by what a child's hook says about its parent). `wait` reaches
  any fish: it only reads.
- **Sessions only the hook reports** (not launched by the aquarium) command through `fishbots`, which reads the
  person's token from the file. "Também as sessões abertas fora do aquário" in Preferences (on by default) turns
  that off: the person's token is then refused when the headers point at a session the aquarium didn't launch
  (`launched` in its whereabouts, set by the app at birth and never taken from a hook). It's a guard rail, not a
  lock: such a session runs as the person and can read the file and leave the headers out.
- **After a restart** the sessions' tokens are dead. `fishbots` sends `FISHBOTS_TOKEN` first and, refused with 401,
  the file's (read again on every call), so a restored session goes on as one the aquarium launched with the
  person's token, and `fishbots wait`, which keeps waiting across a restart, keeps working. The token reaches curl
  on its stdin (`-H @-`), not on the command line.

`fish` is `source:entity`, or the start of the entity when only one fish has it. `GET /state` says what each fish
takes right now (`can`) and who launched it (`parent`). From the command line: `fishbots spawn | reply | stop |
wait`; the `fishbots-orchestrator` skill (`fishbots skill install`) teaches a coding agent the cycle.

- `wait` and `spawn` hold the HTTP answer, like permission requests do (`Server.deferred`, a list of handlers).
- `wait` is an output (point 8): `SessionControl` is an `EventSink` that answers when the right `TankEvent` comes.
  It answers a moment after the turn ends, so the last reply has been read. A fish that left answers `gone`.
- A fish that was just sent a line still stands at "done" from the turn before; `wait` ignores how it stands until
  it changes state.
- `reply` types one line into the terminal (line breaks become spaces). A long brief belongs in `spawn`'s prompt,
  which goes as an argument of the agent's command, not typed.
- `spawn` answers when a fish of that agent shows up in the pane it opened (the hook's `X-Where-*` say which pane).
  If none does in time (no hook installed, or the agent asks something first, like trusting the folder), it
  answers 504 with `where`.
- Some agents' hooks don't run in the terminal (Codex runs them in its daemon: no pane, no parent, another pid).
  Then the new fish of that agent, in that folder, that came from no terminal is the one, and it's put in the pane
  (`Whereabouts.put`), so reply and Esc reach it.
- The new pane doesn't have the asker's environment. What picks the agent's account or profile travels in `env`:
  `fishbots spawn` sends its own `CLAUDE_CONFIG_DIR` and `CODEX_HOME`, and whatever `--env` names.
- A session interrupted with `stop` (or with Esc by hand) has no hook event for it. In Rex and Herdr its terminal
  says the program went idle, and a fish still busy two seconds after that becomes idle (`TerminalPrograms`), which
  `wait` takes as stopped. In other terminals (tmux, iTerm, Ghostty) a session sent Esc through the aquarium becomes
  idle once nothing more is heard from it for a few seconds (`TerminalPrograms.interrupted`).
- Codex runs its hooks in its app-server daemon when one is running, with the daemon's environment (the terminal it
  was started from, long ago). Its hook (`plugins/codex/session-env.sh`) then takes the pane, the port and the leader
  from the session's own terminal process (a codex with a tty in the hook's folder); with two of them in one folder
  it can't tell, and reports no pane.

**Launchers**: where a session is born. Creating one belongs to the host (Rex, Herdr, iTerm, tmux), not to a
fish, so it's a registry next to the providers:

```swift
struct LaunchRequest {
    let command: [String]          // from the provider
    let cwd: String
    let label: String?
    let near: [String: String]?    // the asker's whereabouts: the new session opens where it is
    let tab: Bool                  // a tab of its own, not a pane next to the asker's
    let siblings: [[String: String]]   // the asker's other children, oldest first: the new pane joins their column
    let env: [String: String]      // FISHBOTS_PARENT=…, FISHBOTS_TOKEN=…, the account's variables
}

protocol SessionLauncher: AnyObject {
    var id: String { get }         // "rex", "herdr", "iterm", "tmux"
    var name: String { get }       // as the person knows it (Preferences); the id by default
    var available: Bool { get }
    func hosts(_ whereabouts: [String: String]) -> Bool   // is this where that session runs?
    /// The new pane's whereabouts (rex_session, rex_block…), or an error.
    func launch(_ r: LaunchRequest, done: @escaping (Result<[String: String], Error>) -> Void)
    func close(_ place: [String: String], done: @escaping (String?) -> Void)   // the pane it opened; nil: closed
}
```

A provider says how its agent starts (`launchCommand(prompt:model:) -> [String]?`, nil: it can't be launched; Claude Code
and Codex can); a manifest's `launch` array with `{prompt}` and `{model}` does it for agents without Swift. A session's children
open in the host it runs in (`hosts`); `launcher` in the request picks another, and without an asker in any of
them it's the one chosen in Preferences (General → Sessions → "Open new sessions in", the `launcher` default), or
else the first one installed, in the order Rex, Herdr, iTerm, tmux, background (iTerm before tmux: an installed
tmux needs a server running and often runs inside iTerm; an installed iTerm is a window the person sees). None takes
the focus:

- **Rex:** `rex run --split right -b <the asker's block>`, then `--split below` a sibling (`Launchers.anchor`: the
  column stays about even); with `tab`, `rex run -s <the asker's session>`, a new window.
- **Herdr:** `herdr-core run --bg`, a terminal that stays alive with no one attached; it's the asker's child in
  Herdr too (`--parent`, outliving it, and without Herdr's own notes typed into the parent).
- **iTerm:** AppleScript (it works with iTerm as it comes; the Python API would have to be turned on):
  `split vertically` the asker's session (by its unique id, the part of `ITERM_SESSION_ID` after the colon), then
  `split horizontally` a sibling; with `tab`, `create tab` in the asker's window; what had the focus there gets it
  back. iTerm runs a command without a shell, so the command is a small script in the user's temporary folder that
  removes itself, takes out the variables that say where a session runs or whose child it is (a new iTerm session
  has the environment iTerm was started with: started by an Apple Event from a Rex pane, it would carry that pane's
  `REX_BLOCK`), goes to the folder and runs the agent through the login shell. `close` hangs up what runs on the
  session's tty, then closes it (iTerm would otherwise ask). Needs the Automation permission for whoever sends the
  events (the app; macOS asks once). The pane's whereabouts are `{"term": "iTerm.app", "iterm": <unique id>}`; the
  hooks' `X-Where-Iterm` (the whole `ITERM_SESSION_ID`) is cut to the same id when it arrives.
- **tmux:** `split-window -d -h -t <the asker's pane>`, then `-v` under a sibling; with `tab`, `new-window -d -a`.
- **background:** no terminal at all (point 12): the last resort, and what a parentless spawn falls back to.

A spawn that no session in a pane asked for (the menu, the assistant, a plain shell) has nothing to open beside:
in Rex it gets a session of its own, named after its task; in iTerm, a tab in its current window (a window, if
there's none); in tmux, a window in the most recent session.

A new host is a `SessionLauncher` registered in `Launchers`.

**Lineage:** the launcher sets `FISHBOTS_PARENT=<source:entity>` in the pane and the shared hook forwards it
(`X-Where-Parent`), so the child says whose it is from its first event; the app also notes it when the fish is
born, for hooks that don't. It lives in the fish's whereabouts (`parent`), so it's remembered on reopen. The caller
of a control route is the fish its token was given to; with the person's token, the one the `X-Where-*` headers the
CLI sends point at (the same ones the hook sends), so an orchestrator doesn't need to know its own id. A fish with children is the leader: no "orchestrator" provider.

**In the tank** (`Schools.swift`): from its first child until its session ends, the leader is drawn as the theme's `leader` kind (the
nautilus, with a chamber of its shell lit for each session of its school at work), bigger and lit up, and goes on a wide round of the open
water, brisk while any of its school works (it never settles on the sand, where they'd have no room behind it). Its children are smaller, dressed with its
markings and fin in their own project's color, with "↳" before their name, and keep a V behind it; one that's doing
something goes and does it and comes back, whoever waits for you still comes to the glass, a sick one still sinks.
Every session the aquarium starts, a leader's children included, hatches from the clutch of eggs instead of dropping
in from the surface (`Scenery.expect`, `hatching`). A thread of light ties each one to the leader wherever it is, and shows what goes between them: a bubble of light
down to a child that was just told something, a short pulse up for every tool it uses, a pearl up when it finishes
(strung behind the leader with the others, until the leader finishes and lets them go); taut and blinking amber to
one that waits for you, red and slack to one in error. While the leader waits on its school (`fishbots wait`) it
holds still, turned to them, with the threads to those it waits for lit; when the last one finishes they close in
around it for a moment. The leader's card lists its school with
each one's state and last line (a click opens that fish's card), and what one of them asks is answered right there
(a permission, a question with a menu); a child's card has a tag for its leader. A card's history has what was said
to the session too (`Tank.told`), among what it did about it.

**From the aquarium:** "Nova sessão…" (the Sessions menu, ⌘N, the menu bar, and a click on the clutch of eggs on
the sand, `Scenery.eggs`) asks for the task, the folder, the
agent and the model, and opens the session through the launchers as nobody's child (`SessionControl.open`); with
its checkbox on, the session starts with the orchestrator skill in hand. In Rex it gets a
session of its own named after the task (`rex new`), where its children's panes will go. The aquarium stays in
front and its fish hatches from the clutch of eggs; Rex only comes forward if no fish hatched in 8 s (the agent is
probably asking something first).
It runs on
the account of that agent's most recent session in the tank (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, read from where its
conversation file is kept).

**Guards:** the Preferences switch; 6 children at work per parent (the ones that finished and sit at their prompt do not count) and depth 1 (a child doesn't launch children);
permission requests of the children stay with the person; `spawn` takes no extra arguments for the agent, so it
can't ask for a session that skips permissions; the token (above): the server already refuses browsers, and
without one any local process could start a session with any prompt.

### 12. The resident assistant and its brains
Status: implemented (`Assistant.swift`, `AssistantCard.swift`, `Brains.swift`, `AgentCLIs.swift`).

The same idea as point 11, one step further: the assistant isn't a feature with a model in it, it's **an ordinary
agent session without a pane**, run by the aquarium in a folder of its own. The app stays the bus and the window.

```swift
protocol Brain: AnyObject {
    var id: String { get }                 // "claude-code", "codex", "command"
    var name: String { get }
    var agent: String? { get }             // whose command line it runs (AgentCLIs)
    var installed: Bool { get }
    func ask(_ text: String, setup: BrainSetup, events: @escaping (BrainEvent) -> Void)
    func decide(_ request: BrainRequest, allow: Bool)
    func interrupt()
    func sleep()
    func terminalCommand(session: String) -> [String]?   // to go on with the conversation in a pane
}
```

`BrainEvent` is what it says while it answers: `started` (the conversation's id, to resume later, and the model),
`text` (more of the answer), `tool`, `permission`, `done`, `failed`. A new brain is a `Brain` registered in `Brains`.

- **Claude Code** (`ClaudeBrain`): `claude -p` with `--input-format stream-json --output-format stream-json
  --permission-prompt-tool stdio`. One process kept between turns; the answer comes in pieces
  (`--include-partial-messages`); a permission request comes through the stream as a `control_request`
  (`can_use_tool`) and is answered on the same stream, which is what lets the card ask with no terminal. Later
  starts pass `--resume <id>`.
- **Codex** (`CodexBrain`): `codex exec --json`, one run per turn, `exec resume <id>` afterwards. It can't ask in
  this mode: it runs in its `workspace-write` sandbox with the network on (for the `fishbots` command).
- **A command** (`CommandBrain`): the instructions, the notes, the context and the question on its input, the
  answer on its output. No memory of its own.

**Its folder** (`~/Library/Application Support/Fishbots/assistant`, made by `Assistant.prepareFolder`): `CLAUDE.md`
and `AGENTS.md` (the instructions; rewritten by the app while they carry its `fishbots:managed` line), `notes.md`
(its memory, imported by `CLAUDE.md`) and `.claude/skills` with the aquarium's skills (`fishbots skill install`).
The agent's own conventions do the rest: nothing about memory or skills is code in the app.

**What it knows:** `Assistant.context()` goes in front of each question, an `<aquarium>` block with every session
(state, how long, branch, what it asks or wants permission for, what it takes), what else asks for attention and the
journal: the whole day the first time, what's new since the last answer afterwards. The journal is kept on disk
(`Journal.save`) and served at `GET /journal`.

**What it may do:** the agent's own allow rules apply first (those requests never reach the app). Of what does
reach it, `Assistant.allowedByItself` lets through the file tools inside its folder and the `fishbots` commands
that only look (`show`, `journal`, `wait`); the person's "always" rules (`assistantAllow`: a tool's name, or
`Bash:` and the first two words of a plain command, never one with pipes or redirections) come next; the rest is
asked on the card. It acts on sessions through the control routes, with their guards.

**Not a fish:** its brain fires the person's hooks like any session. `Assistant.owns` recognizes them by their
`cwd` (its folder, where nothing else runs) and `Routes` drops them, the permission hook included, so it's never
taken for a session. In the tank it's a presence of the app's own (`fishbots:assistant`, kind `moray`), whose
state is the assistant's: `busy` thinking, `waiting` for leave, `done` with something unread; `Presence.open` is
what a click on an app-owned presence runs. A theme dresses it through `looks`, like any presence kind.

**Each agent's command line** (`AgentCLIs`, Preferences → Agents): binary, extra parameters and variables, used by
the brains and by the providers' `launchCommand`, so a session started from the aquarium runs the way the person
runs that agent (an alias does neither). The person's own parameters are their choice; `spawn` still takes none
from the caller.

**Telling on its own** (`Assistant.watch`, `POST /assistant/watch`, `fishbots watch <fish> [note]`): the brain asks
to be woken when a session stops. The assistant is one of the tank's outputs (`AssistantEars`, point 8): when that
fish finishes, asks or breaks, it starts a turn by itself with the session's reply in it, and the answer waits on the
creature (`done`) until the card is opened.

**Sessions with no terminal** (`Background.swift`): `BackgroundLauncher` is the last launcher in `Launchers`, picked
when no terminal host is there (or when a parentless spawn fails in one, as tmux with no server running). It runs
the agent through a brain of its own (`Brains.fresh(agent)`: each session has its process and conversation), in the
session's folder. The agent's hooks make its fish as always; `Background` puts the fish in its place
(`whereabouts["background"]`) once the brain says the conversation's id, which is how `spawn` finds what it launched.
`TerminalAgentProvider` asks `Background.of(fish)` before the terminal: `reply` is the brain's next turn, `stop` its
interrupt. A permission request from its stream goes through `permissionAsked` (Routes), the same path as the
permission hook, so the card, the notch and a leader waiting on it see it alike; the hook itself, if installed, gets no
decision for these sessions (`Background.owns`), or the same thing would be asked twice. `LaunchRequest` carries
`agent`, `prompt` and `model` for launchers that don't run `command` in a terminal.

Still open: the token for the control routes (the assistant acts through them), the morning summary and "while you
were away" told by the assistant, holding the shortcut to talk, and a background session surviving the app (today
its agent goes when the app quits).

### 13. Other devices (Remote.swift)
The aquarium seen from another device, like an iPhone app. The sessions keep running on the Mac: the device
watches, answers permission requests and replies, and nothing is started on it. A reply goes into the session's
terminal through the provider, exactly as the card sends it (`Cards.sendReply`, `Cards.decide`).

Off unless **Preferences → General → Other devices** turns it on (`remoteAccess`). Then a second listener opens on
every interface, on the local port + 1 (7778), announced over Bonjour as `_fishbots._tcp`. It speaks plain HTTP inside
TLS 1.2 with a pre-shared key (`TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256`, identity `fishbots`, the PSK being
HMAC-SHA256(key, "fishbots-psk-v1")): no certificates, a device without the key fails the handshake, and ECDHE gives
each connection a key of its own (forward secrecy). `RemoteTLS.parameters` builds the connection on both sides.

**Each device has a key of its own** (`RemoteDevices.swift`, `remote-devices.json`, 0600): the listener holds every
paired device's key, each under its identity, and TLS picks the one the device names. The QR code carries a key no
device has yet (its `id` and `key`); the first request with it pairs that device under the name it sends
(`X-Fishbots-Name`), and the QR moves on to a fresh key. Revoking a device (Preferences, or `POST /remote/revoke
{"id"}` on the local server) takes its key out: the listener opens again with the rest, its streams close, and its
handshake fails from then on. TLS doesn't say which of its keys was used, so each request names its device in
`X-Fishbots-Device`; that only decides how it's listed and whose key seals its notifications (every device that
can connect is one the person paired). The single key of earlier versions became the device `fishbots`, so a phone
paired before stays paired.

Listing the suite doesn't stop the server from agreeing to plain PSK, so `Remote.admits` checks the agreed suite
after the handshake, and also the address: only private networks get in (10/8, 172.16/12, 192.168/16, Tailscale's
100.64/10, link-local, fc00::/7), so a forwarded port or a global IPv6 address doesn't open it to the internet. The keys survive restarts, so a
paired phone stays paired; **Forget all** (or `POST /remote/forget` on the local server) takes every device out.
The QR code carries
`fishbots://pair?v=1&name=<Mac>&port=7778&hosts=<IPv4,…>&ts=<MagicDNS name>&id=<device>&key=<base64url>`: Bonjour finds the Mac
on the same network; away from it the device tries `ts` (the Mac's tailnet name, found by a reverse lookup of its
100.x address, stable when addresses change) and then `hosts`. That needs the Tailscale app on the Mac: Tailscale built
into another app runs its own node inside that process and makes no address on the Mac, so it can't reach this
listener. Preferences says which case it is. `GET /remote` on the local server returns the same link.

Only these routes answer on the remote listener. The others stay local: events and hooks never come from a device.

| Route | |
|---|---|
| `GET /state`, `/packs`, `/packs/files`, `/journal` | the same as locally |
| `GET /stream` | Server-Sent Events: `state` (the whole `/state`, one line, when it changes), `permissions` (the pending list, when it changes) and `event` (each `TankEvent`, as it happens; `Remote` is an `EventSink`). Both snapshots come first, on connecting |
| `GET /permissions` | `{"permissions": [{id, source, entity, label, tool, summary, since, question?, questions?}]}` |
| `POST /permissions/<id>` | `{"decision": "allow"\|"deny"}`, `{"answer": "…"}` (a question with a menu: its number or label, or free text) or `{"answers": {"question": "answer"}}` (a form) |
| `GET /said?source=…&entity=…` | the session's last reply (`text`, `markdown`: whether it's the agent's own markdown, `asked`), up to 20,000 characters; kept out of `/state` because it can be long |
| `POST /reply` | `{"source", "entity", "text"}`: a question with a menu waiting on that fish takes it as its answer; otherwise the session gets it, if it `can` take a reply (409 if not) |
| `GET /spawn/options`, `POST /spawn` | what can be opened (agents, recent folders) and opening a session on the Mac: `{"agent", "cwd", "task"}`, answered once its fish is born |
| `GET /assistant`, `POST /assistant/ask`, `/decide`, `/stop`, `/new`, `/seen` | the resident assistant: its last turns, whether it's thinking, what it asks to use (with the "always" rules it offers); ask it `{"text"}`, decide `{"allow", "always"?}`. The stream sends `assistant` each time the conversation changes (the answer as it comes) |
| `POST /theme` | `{"id": "…"}`: the Mac takes that theme, as if chosen in its menu (the device can also keep one of its own without telling the Mac) |
| `POST /stop` | `{"source", "entity"}`: interrupts the agent, if it `can` |

**The iPhone app** (`iOS/`, built by `scripts/ios.sh project|sim|device`) is the engine (`scripts/engine-files.txt`,
the same list the screen saver builds) plus `RemoteTLS.swift` and its own files: `MacLink` keeps the stream open and
makes the requests, trying Bonjour, then the tailnet name, then each address; `TankMirror` (shared with the screen
saver) applies each `state` to a tank of its own, so the fish swim there and only who's there comes from the Mac;
`Pairing` keeps the link in the Keychain (this device only). Allowing a tool asks for Face ID first. A fish's card is
the Mac's, drawn with the same pieces: its portrait (`Portraits.swift`: `FishPortraits` on `ShaderSheet`, also behind
the pack previews and the theme swatches) and its last reply laid out by `ReplyText`, which builds on AppKit or UIKit.
The phone can keep a theme of its own (`TankMirror.themeOverride`) or hand it to the Mac (`POST /theme`), and hide the
fish's names. Its log (packs it mirrored, drawings that didn't compile there) is `Library/Caches/fishbots.log`. The Xcode
project is generated by XcodeGen into `build/ios/` from the engine's list, so there's nothing to keep in step by hand.
In Debug builds `fishbots://test?do=allow|deny|answer:<text>|open:<fish>|reply:<text>|close` presses the buttons,
for testing in the simulator (`xcrun simctl openurl booted …`).

**Notifications through iCloud** (`CloudNotes.swift`, the default): no push key and no server. The Mac app, signed
with the iCloud container `iCloud.io.vitalbh.fishbots` (scripts/app.sh with `FISHBOTS_TEAM`: scripts/mac-signing.sh
gets its provisioning profile), writes a `Note` record (`fb`: the sealed text, `sent`) to the private database, in the
zone of the device it's for (`device-<id>`). The phone (`iOS/Cloud.swift`) makes that zone, a query subscription on
it with `shouldSendMutableContent` and `desiredKeys`, and tells the Mac (`POST /push/register {"cloud": true}`); Apple
then notifies it within a second of the write. The extension reads the sealed text from the CloudKit payload
(`PushKey.sealed(in:)`) and sets the category (its buttons) from the sealed `k`. Notes are deleted after ten minutes.
Both apps on the same Apple ID. `CloudNotes.available` checks the entitlement at run time, because CloudKit stops an
app that asks for a container it isn't entitled to; a build without a team has no iCloud. `POST /push/test` on the
local server sends the test and says which ways it went. A phone that also registered an APNs token (below) gets
notifications that way instead.

**Notifications** (`Push.swift`, an `EventSink`): when a session asks permission, stops and waits, or breaks, and no
device has the stream open, the Mac sends a notification to each registered phone (`POST /push/register` on the
remote listener) straight to APNs, signing its provider token with the account's .p8 key (Preferences → General →
Notifications on the iPhone: Key ID, Team ID, the key). There's no server of ours in between. What it says goes sealed
(`PushSeal`: ChaChaPoly, the key derived from the pairing key by HKDF): Apple sees "A session needs you" and its
category; the phone's notification service extension (`iOS/Notify`) opens it with the derived key, kept in a Keychain
group it shares with the app, so it never holds the key that talks to the Mac. The categories carry buttons: Allow and
Deny (they need the phone unlocked), Reply with a text field; they go to the Mac from the notification, the app
closed. Each session's newest notification replaces its older one (`apns-collapse-id`, a hash of the fish's id).
`FISHBOTS_PUSH_DUMP=<folder>` writes the payloads instead of sending them, for `xcrun simctl push booted <file>`
(the simulator shows them without running the extension). Push needs a paid developer account: `FISHBOTS_PUSH=1
scripts/ios.sh device` adds the entitlements and the extension (the simulator always has them).

The phone has **sound** too (`iOS/Sound.swift`): the Mac's Synth and `Music` on the mirrored tank, so each fish calls
when it changes and the ambient music plays if it's on; the packs' sounds come along (`GET /packs/files?sounds=1`,
base64). `Music` asks about the person through closures (`focus`, `userMusic`, `loudness`, `checkInView`): the Mac
answers from Attention, NowPlaying and InView, the phone keeps the defaults. And it can **start a session** on the Mac
(`GET /spawn/options`: the agents that start from the aquarium, recent folders; `POST /spawn {agent, cwd, task}`,
answered once its fish is born or with what went wrong): it opens in a terminal there, like one from the eggs, after
Face ID on the phone.

On the phone the tank is drawn as a wider one (560 points at least) shrunk to fit, so a phone held upright isn't a
third of the Mac's tank crowded with its scenery; the names are drawn over it at their own size, placed by
importance (what needs you, then the sessions, then the rest), and a name that would land on another waits for room.
A light on the glass that's fine shows no name. Touching a presence opens its source's card (all its presences);
touching the assistant, the conversation with it.

Still open: a widget on the phone's home screen (it needs the notifications to stay up to date).

## Order of work

1. **Session providers:** move Claude Code, Codex and the generic source behind `SessionProvider`. Biggest win for the
   code even if everything stays open, and it makes new agents (Gemini CLI, Aider, Cursor…) one file each.
2. **Themes as uniforms + JSON**, with the current look as the built-in theme.
3. **Visualizer protocol**, porting the six current modes.
4. **Fish kinds** with the generated shader dispatch, porting the current species.
5. **Tool behaviors table** and **fauna** as creatures.
6. **Pack loader** (themes, styles, fish).
7. **Sinks** and **fish menu actions**.

Each step keeps the app working and looking the same; the tour (`scripts/tour.sh`) is the regression check.
