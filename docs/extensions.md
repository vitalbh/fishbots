# Extension points (design)

Status: the order of work below is implemented (v0.4). Goal: every part people will want more of (themes, session providers,
visualizers, fish…) gets a clear seam, so that it can grow from two places without touching the core:

1. **Built-ins** in this repository (MIT): Claude Code, Codex, the current visualizers and the tank as it is.
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
stingray, a pleco on the glass, an electric eel, a black caiman for the shark).

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
- `looks`: how the theme dresses built-in things, by id. The meaning stays, only the drawing changes:
  - a **piece of scenery** (`rock`, `shell`, `chest`, `coral`) drawn by one of the pack's scenery pieces, in the same
    place and with the same behavior (the chest still opens the summary). A chest's drawing gets how open it is in
    `extra.y` (instead of the seed) and glows while it's open. The piece doesn't need to be in the theme's `scenery`;
  - a **presence kind** plugins send (`"bottle": "floating-lantern"`): drawn as one of the pack's presences that moves
    the same way (checked on load), keeping its label, state, link and sound. A plugin that wants its own drawing
    sends `"override_theme": true`;
    The app's own variants work too: `"shark": "hammerhead"`, `"helm": "rusty-helm"`, `"bottle": "deep-bottle"`
    (the deep sea's barnacle-crusted bottle, plankton glowing in the state's color), `"chest": "safe"` (a ship's
    safe) and `"chest": "fish-trap"` (a woven fishermen's trap), for the chest piece and the chest presence. Built-in
    scenery only for themes that list it: `helmet` (an old diving helmet on the sand), `wreck` (a sunken ship far away)
    and `mangrove` (prop roots coming down at the sides). Built-in creatures for a theme's `fauna`: `anglerfish`,
    `sunfish`, `manatee`, `seahorses`.
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

The shader's helpers (`sd_box`, `sd_seg`, `sd_tri`, `smin_k`, `vnoise`, `hash21`, `vor_edge`) can be used. A theme
lists the pieces it wants in `"scenery"`, mixed with the built-in ones (`rock`, `shell`, `chest`, `coral`); a pack's
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
Status: implemented (`SessionControl.swift`, `Launchers.swift`), with launchers for Rex, Herdr and tmux (the tmux
one was written from tmux's manual and hasn't run against a real tmux yet).

The aquarium already sees every agent in every client and can type into most of them. Letting a session use that
makes it an orchestrator: **the orchestrator is not a feature of the app, it's an ordinary agent session** that
calls the aquarium. The app runs no model and holds no API key; it stays the bus and the window. Any agent can lead,
and the leader is a fish like the others (card, timeline, permissions).

**Control routes** (`POST /control/…`, off until "Sessões podem comandar outras" is on in Preferences; the same
checks as the card apply, so nothing is typed where the card wouldn't type):

| Route | Body | Answer |
|---|---|---|
| `/control/reply` | `fish`, `text` | ok, or why not (not at its prompt, another program in front…) |
| `/control/stop` | `fish` | ok |
| `/control/wait` | `fish` (one or many), `states`, `timeout` | held until one of them stops working (done, waiting, error, idle; or the `states` asked for): which, its state, its last reply |
| `/control/spawn` | `agent`, `cwd`, `prompt`, `label`, `launcher`, `beside`, `env` | held until the fish is born: `fish`, `state`, `parent`, `where` |

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
  `wait` takes as stopped. In other terminals it stays "busy" until it's sent something.

**Launchers**: where a session is born. Creating one belongs to the host (Rex, Herdr, tmux), not to a
fish, so it's a registry next to the providers:

```swift
struct LaunchRequest {
    let command: [String]          // from the provider
    let cwd: String
    let label: String?
    let near: [String: String]?    // the asker's whereabouts: the new session opens where it is
    let beside: Bool               // a pane next to the asker's, not a tab of its own
    let env: [String: String]      // FISHBOTS_PARENT=…, the account's variables
}

protocol SessionLauncher: AnyObject {
    var id: String { get }         // "rex", "herdr", "tmux"
    var available: Bool { get }
    func hosts(_ whereabouts: [String: String]) -> Bool   // is this where that session runs?
    /// The new pane's whereabouts (rex_session, rex_block…), or an error.
    func launch(_ r: LaunchRequest, done: @escaping (Result<[String: String], Error>) -> Void)
}
```

A provider says how its agent starts (`launchCommand(prompt:) -> [String]?`, nil: it can't be launched; Claude Code
and Codex can); a manifest's `launch` array with `{prompt}` does it for agents without Swift. A session's children
open in the host it runs in (`hosts`); `launcher` in the request picks another, and without an asker in any of
them it's the first one installed. None takes the focus:

- **Rex:** `rex run -s <the asker's session>`, a new window (tab); with `beside`, `rex split -b <the asker's block>`.
- **Herdr:** `herdr-core run --bg`, a terminal that stays alive with no one attached; it's the asker's child in
  Herdr too (`--parent`, outliving it, and without Herdr's own notes typed into the parent).
- **tmux:** `new-window -d -a -t <the asker's pane>`; with `beside`, `split-window -d -h`.

A new host is a `SessionLauncher` registered in `Launchers`.

**Lineage:** the launcher sets `FISHBOTS_PARENT=<source:entity>` in the pane and the shared hook forwards it
(`X-Where-Parent`), so the child says whose it is from its first event; the app also notes it when the fish is
born, for hooks that don't. It lives in the fish's whereabouts (`parent`), so it's remembered on reopen. The caller
of a control route is found by the `X-Where-*` headers the CLI sends, the same ones the hook sends, so an
orchestrator doesn't need to know its own id. A fish with children is the leader: no "orchestrator" provider.

**Guards:** the Preferences switch; 6 children alive per parent and depth 1 (a child doesn't launch children);
permission requests of the children stay with the person; `spawn` takes no extra arguments for the agent, so it
can't ask for a session that skips permissions. No token: the server already refuses browsers, and a
local process could type into the terminals by itself.

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
