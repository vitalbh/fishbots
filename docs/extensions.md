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
- **Packs on disk.** `~/Library/Application Support/Fishbots/packs/<id>/pack.json` declares themes, music styles and
  fish (each with a `.metal` file). Packs are data and GPU code only: they can't run anything on the Mac. Everything is
  validated on load; a broken pack is skipped and reported in the menu.

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

**Adding an agent with hooks** (as implemented in `Providers.swift`):
1. `plugins/<agent>/hook.sh`: a one-liner that runs `plugins/common/hook.sh <route> '<glob of its executable>'…`
   (forwards stdin and the `X-Where-*` headers; `FISHBOTS_HOOK_LOG=1` keeps the last event to study the format), plus
   the agent's own hook config (`hooks.json`). Permissions, if its hook format matches Claude Code's:
   `plugins/common/permission.sh <route>`.
2. A provider registered in `Providers.registerBuiltIns()`: `id`, `routes`, `profile` (timbre, fish kind) and
   `processNames` (words in its process path, used to check the Rex pane before typing and whether a saved session is
   still alive). Subclass `TerminalAgentProvider` to get reply/stop through Rex, iTerm and tmux.
3. Translate its events: if the JSON looks like Claude Code's (`session_id`, `hook_event_name`, `tool_name`, `cwd`,
   `transcript_path`), call `ClaudeCodeHook.apply`; otherwise rename its fields/events in `handle` first.
4. Optional: a branch in `Transcript` for title, branch, context and last reply.
Script plugins and `POST /event` become one more provider ("generic") with no capabilities beyond going to a link.

### 2. Fish kinds
Today: `Fish.species` (0–5) is decided by an `if` chain on the source and terminal, and the shader picks the drawing
with another `if` chain (`draw_fish`, `draw_octo`, `draw_ray`).

```swift
struct FishKind {
    let id: String              // "neon", "octopus", "stingray"…
    let metal: String           // a Metal function: float4 draw_<id>(float2 c, float phase, float glow, float4 col, float4 extra)
    let extent: SIMD2<Float>    // quad size relative to the fish size
    let swim: SwimStyle         // speed, wiggle, depth preference
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

Ideas for packs: coral reef, deep sea (dark, bioluminescent), Japanese pond (koi), night aquarium.

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
| `anchor` | `sand` (standing on the sand: the bottom of the drawing, c.y = -1, a little buried), `surface` (floating, riding the waves), `float` (in the water, at `height`) |
| `size` | its height, as a fraction of the tank's height (default 0.06) |
| `extent` | the quad's width and height, relative to `size` (default `[1, 1]`) |
| `at` | where the copies go, 0…1 from the left (one number or a list); or `count`, spread out from the id |
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

### 5. Tool behaviors
Today a hard-coded `switch` maps tool names to an action (nibble, bubbles, forage, peek, mail), a label icon and a
timbre. It becomes a table that providers extend (`"Bash": .bubbles`, `"mcp__*": .mail`, and e.g. "the agent runs the
tests" → a new action), with glob patterns for tool names.

### 6. Music styles and timbres
`Style` is already data. It moves into a registry and packs can add styles (bpm range, scale, progressions, rhythm,
voices). Timbres stay in Swift for now (`Synth.render` is real-time audio code).

### 7. Fauna
Each creature (crab, turtle, whale, snail, lanternfish) becomes a `Creature` with `update`, sprites per layer
(background, middle, front) and a rule for when it shows up. A theme lists which creatures it uses.

### 8. Outputs (sinks)
The opposite of providers: `EventSink` receives what happens in the tank (state changes, done, error, permission
requests) and sends it somewhere: a webhook, Slack, Home Assistant, a desk light.

### 9. Fish menu actions
Providers and plugins can add actions to the fish menu and the card ("Abrir o PR", "Rodar os testes de novo", "Abrir
no editor"), each with a condition (`when: fish.link != nil`).

### 10. Interface languages
Not a code extension point but the same idea: the on-screen text moves into string tables (pt, en…), and packs can
bring translations.

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
