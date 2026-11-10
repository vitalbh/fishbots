# Fishbots

A living aquarium on your Mac that doubles as a monitor: every agent, project or thing you keep an eye on becomes a fish, and what's happening becomes music. You hear the work: who's busy, who's done and who's waiting for you.

Built in Swift, with Metal (water, light and fish drawn in the shader) and a custom synthesizer on AVAudioEngine.

The code, protocol, CLI, scripts and file names are in English. The interface is in Portuguese or English (Preferências → Geral → Idioma; automatic follows the Mac's language); menu items and labels below are quoted in Portuguese, with a short gloss. Fishbots was called Aquário before; its old settings, folders and `AQUARIO_*` env vars are picked up automatically. The old Portuguese names (protocol fields and states, routes, headers, CLI commands, script arguments, env vars, `config.json` keys, `ir.sh`) are still accepted.

## Running

```sh
swift run -c release            # or: scripts/app.sh  →  build/Fishbots.app
FISHBOTS_DEMO=1 swift run -c release   # opens straight into demo mode
open --env FISHBOTS_HOUR=18.5 build/Fishbots.app   # see another hour's colors (dawn, late afternoon, night)
open --env FISHBOTS_GPUSTATS=1 build/Fishbots.app  # prints the GPU time per frame every 5 s (FISHBOTS_BLOOM=0 turns the glow off)
open --env FISHBOTS_CATALOG=file://$PWD/community/index.json build/Fishbots.app   # the pack catalog from this checkout (off: none)
open --env FISHBOTS_PACK_BUDGET_MS=50 build/Fishbots.app   # how slow (ms per frame) before a pack is looked into (default 33)
```

Keys and shortcuts:
- **Click a fish:** go to it. **Right-click:** fish menu. **Click empty water:** feed.
- **Tab / ⇧Tab** (aquarium in front): goes through the sessions, the ones waiting for you first, opening each card with its reply field ready (type, Enter sends). On the chosen card: **⌘↩** go there, **⌘R** hear the question, **⌘D** speak the reply, **A / N** allow or deny a permission request, **Esc** close. The card's footer lists only the keys that fish takes.
- **Global shortcuts** (any app, set in Preferências → Geral): **⌃⌥F** go to whoever has waited longest, **⌃⌥R** hear their question, **⌃⌥M** reply by voice.
- **Click a pearl:** what was done around that time. The day's pearls are a timeline on the sand, from the morning (left) to now (right).
- **Drag a fish:** it's pulled along a little and swims back when you let go. **Drag through the water:** a short current (snow, seaweed and fish go with it). **Double-click the water:** a knock on the glass, and the idle fish and the schools come to look. **Scroll over the water:** sprinkles food.
- **D** demo · **M** sound · **S** focus mode · **T** float above windows · **F** food · **W** widget mode: a little frameless window in the corner of the screen, always on top and on every Space, showing only who needs you (drag the water to move it; W again to come back).
- **L** cycles the labels: **minimal** (default: the short title, or the name, plus a second line only when it matters: whenever it needs you, and for a few seconds when something happens), **full** or **none**. Everything else is in the hover card.
- Closing the window doesn't quit: the aquarium stays in the **menu bar** (🐠, with whoever is waiting for you).

To avoid the automation permission prompt on every build, create a self-signed **Code Signing** certificate named `Fishbots Dev` in Keychain Access (Certificate Assistant → Create a Certificate). `scripts/app.sh` will use it.

## Mechanics: the living aquarium

- **Error = sick fish:** it fades, turns nose-down and slowly sinks. Fish from the same project gather around it. When it recovers, it does a little lap. If the error lasts more than 12 min, the water around it clouds and it becomes an urgent alert (once).
- **Octopus with broken CI:** releases a cloud of ink.
- **Waiting for you:** a queue at the glass in order of arrival, and whoever has waited longest grows bigger. After 3 min, the glass in front fogs up.
- **Subagents become fry:** each Task/Agent spawns a baby fish that swims behind the session and leaves when the subagent finishes.
- **Context = fat:** the fish grows fatter with the session's context usage (the `usage` of the last response in the transcript, over 200k, or 1 million once it passes that). A fat fish swims slower, and the label shows "% contexto". While compacting (`PreCompact` hook), the label shows "🫧 compactando…" and the fish shrinks, trailing a thread of bubbles. At the end (the compact `SessionStart`, which doesn't count as a new session), it rereads the context and takes its new size.
- **Animation per tool:** Edit/Write nibbles the nearest plant (dropping green bits), Bash puffs out bubbles, Read/Grep/Glob noses around in the sand, and WebFetch/WebSearch rises to peek at the surface. Each animation lasts a few seconds; repeating the same tool extends it.
- **Last response in the card:** when the session has stopped (finished, asked something or is idle), the card shows the end of the agent's last message (the last lines, without markdown markup) and a **ver tudo** ("see all") that opens the whole response, scrolling inside the card. It comes from the hook (Codex) or the transcript (Claude).
- **Reading aloud:** the 🔊 next to the last response reads it aloud (the excerpt, or everything if "ver tudo" is open). In the menu, **Ler as perguntas em voz alta** ("read questions aloud") makes the aquarium speak on its own when a session asks you something ("aquariozinho pergunta: …"), outside focus mode and with sound on. It uses the best installed pt-BR voice and ducks the music while speaking.
- **Session actions:** in the hover card (and the right-click menu), **Responder** ("reply") sends a typed line to the session's terminal, with Enter, and **Parar** ("stop") sends Esc. They only show up where typing into the exact spot is possible: Rex (checking that Claude/Codex is in front), iTerm (by session id) and tmux. Reply only works when the agent is idle at the prompt with no permission request open (there, Permitir/Negar apply), and line breaks become spaces. Also in the right-click menu: **Dar um nome** ("give it a name", a nickname stored in the aquarium), **Renomear o painel no Rex** and **Renomear a sessão no Rex** (rename the Rex pane / session). The **🎙** button in the card lets you **talk to the fish**: macOS transcription (pt-BR, on-device when available) fills in the field, and another click stops; then just press Enter. While the mouse is on the fish, or the card is open, it swims in a circle in place.
- **Dots and card:** next to the name, one pearl per task finished today (up to 5) and a red dot if there was an error in the last hour. Resting the mouse on a fish for half a second opens a card with everything: project, where it runs, branch, title, state, how long it's been active, context bar, the model it last answered with (Claude and Codex, from the conversation file), latest tools, today's tasks and, if there's a permission request, Permitir/Negar ("allow/deny") right there.
- **Pace:** the more tools per minute, the faster the fish swims and the more bubbles it leaves in its wake.
- **Pearls of the day:** each finished task leaves a pearl in the sand (hovering shows the project, time and title). They disappear when the day changes.
- **Sleeping:** idle for more than 10 min, it lies down near the sand, closes its eye and lets out "zzz".
- **PR merged:** the octopus rises and leaves through the surface, with light fireworks.
- **Water health:** with errors, the water darkens a little.
- **Current:** high CPU gently pushes the fish and bubbles.
- **The music that's playing:** while Spotify or the Music app plays, a special fish shows up: a big betta with an iridescent tail that dances near the top and lets out notes, named "♪ track — artist". It glows with a burst of notes when the song changes (and from the second song on, leaps out of the water while the new song's name shows at the top; all silent), turns gray and sinks with "⏸ pausado" while paused (and leaves after 5 min), and clicking it brings the player forward; the aquarium's ambient music steps aside meanwhile. When your music pauses, the ambient music doesn't come back by itself (the pause may be for a meeting): the betta asks, quietly (no notification, nothing read aloud), "♪ toco a música do aquário? (clique)"; a click on it or ⌘A says yes, and the question goes away when your music plays again. Its card is a "now playing" card: the album art big and blurred behind it, the song and the artist, the player's buttons and a bar in the album's colors you can click or drag to jump in the song. While it plays, the cover's colors tint the water's light and the aurora (Preferências → Aparência). No polling: the players announce each change themselves. Off in Preferências → Geral.
- **Scenery:** rocks, a big shell and a treasure chest sit on the sand (the theme picks which); the fish swim around them, crabs turn back at them and pearls keep clear of them. **Clicking the chest** opens the summary of the last 2 hours.
- **Sessions come back when the app reopens:** agent sessions are saved now and then (and when the app quits) to `~/Library/Application Support/Fishbots/fish.json`, and come back quietly, with no notices, but only the ones still alive: the process is still running, the Rex pane still has the agent in front, or the conversation file changed in the last 6 hours (and anything silent for over 12 hours is dropped).
- **Background sessions in Rex:** a Claude Code session running in the background ("segundo plano") only shows a client in its Rex pane, so its hooks don't know the pane. The aquarium finds it by the conversation title, which the pane shows too (only when exactly one pane has it), and clicking the fish goes there.

To see it all in action: `open --env FISHBOTS_FAST=1 build/Fishbots.app` (shortens the timings) and `scripts/tour.sh`, which stages each mechanic with test fish and tells you in the terminal what to look at.

## Life in the aquarium

**Each project has its own look.** Besides color and species (which tell the application), each project gets a pattern (plain, stripes, spots, gradient, scales or eye mask) and a fin cut (normal, veil tail, tall dorsal or long fins), always the same for it.

**Water, light and time:** the water is drawn in Metal and lives on its own. Marine snow drifts at three depths (stirred by clicks, the mouse and passing fish); sun rays sweep through it and light it up; everything that swims casts a soft shadow on the sand; the seaweed (thin blades, kelp ribbons and leafy stems) parts around whoever swims through and lets out oxygen bubbles by day; bubbles pop in little rings on the surface, and fish near it show upside down on its underside. The colors follow the hour: an orange dawn, neutral day, golden late afternoon, violet dusk and a blue night with moonlight; the sun (or moon) shines through the surface, crossing it during the day. At night, disturbed plankton glows. Things that glow (sparks, fireworks, notes, the chest, the presences' halos) get a soft bloom. The fish breathe (gills), keep their pectoral fins fluttering, undulate as they swim, and the neons swim as a real school. Preferências → Aparência: glow (off, soft, normal, strong), colors of the hour, marine snow.

**Depth:** plants and rocks in the distance, faded by the water; dark, blurred tufts of plants in the foreground; distant fish smaller and bluer (sessions always stay close and readable); and parallax: moving the mouse shifts the foreground more than the background.

**Ambient creatures:**
- **crabs:** walk sideways on the sand, stop and sometimes bury themselves;
- **turtle:** crosses the aquarium now and then, paddling;
- **snail:** climbs the right-hand glass leaving a trail, and at the top lets go and falls;
- **starfish:** wave an arm on the sand;
- **lanternfish:** show up at night, their little light swaying;
- **whale:** rare, passes far away as a silhouette, with a deep song. It also shows up as a gift when the day passes 10 tasks, once a day.
- **anglerfish** and **sunfish** (deep sea): the anglerfish lives near the bottom with its lure glowing and snaps its mouth open when a fish comes close to the light; the huge sunfish crosses now and then, far away.

**Animations:**
- **jump:** when a big task finishes (more than 5 min or 25 tools), the fish leaps out of the water in an arc, with a splash;
- **cursor:** idle fish come close to a resting mouse; a click near them (not on them) startles them and they flee;
- **waking up:** whoever was asleep yawns (a bubble ring) and stretches;
- **chat:** two idle fish from the same project meet nose to nose;
- **bubble ring:** idle fish blow one now and then;
- **tag:** at night, idle fish play with each other.

## Visualizers

They sit behind the fish and react to each note (at the position and in the color of whoever played it), to the chord, the energy and events. They're aquatic versions of the Jardim de Chuva visualizers:
- 🌟 **plankton:** dots that light up around whoever plays;
- ✨ **underwater aurora:** each piece draws a combination, and the footer shows which one came out. The options:
  - **shape:** vertical curtains or wavy bands up high; by day, it becomes golden sunbeams;
  - **color:** one or two colors, from the style's palette (lullaby lilac and pink, ambient aqua green, lo-fi amber, bossa turquoise) pulled by the chord's color;
  - **breathing:** swells on each chord and fades;
  - **following the singer:** the nearest curtain glides over to the fish that played;
  - **sparkles:** twinkling dots inside the veil;
  - it always dances faster with energy, and is stronger at night;
- 🌊 **living surface:** each note makes a wave on the surface;
- 🎼 **bubble score:** the melody moves right to left, each bubble at the note's height;
- 🌌 **plankton constellation:** each fish's notes linked by thin lines;
- 🌿 **dancing seaweed:** each chord sweeps across the seaweed like a wave, each note kicks the blades near whoever played and lights their tips;
- 🪼 **jellyfish of the harmony:** each chord lets out a jellyfish in its color, which pulses with the notes and drifts up;
- 📡 **sonar:** rings of sound from whoever played, wide and slow for low notes, small and quick for high ones, with an echo;
- ⛈️ **storm** (the deep sea's): lightning strikes the surface on chords, the tank flashes with the music, and heavy music sets a current running;
- 🐟 **school of light:** a school of little bioluminescent fish follows the melody, each note pulling it to its pitch's height and toward whoever played, each chord changing its color, a trail of light behind; a click scatters it;
- 🎆 **light fireworks:** on each event, in any mode, a burst of dots opens in the water (slowed by it) and rises, fading.

The **aurora stays in the background** (default; turn off in Visualizador → Aurora de fundo), and the chosen visualizer appears on top of it. The **Visualizador** menu lets you choose automatic by style (lullaby → plankton, ambient → constellation, lo-fi → score, bossa → surface), random (changes with each piece), off or a fixed one. In the screen saver, since there's no music, they react when fish change state.

## Preferences

**Preferências…** (⌘, or the menu bar menu) has four tabs: **Geral** (open at login, menu bar only, floating, sound and volume, ambient music, a note per tool, reading questions aloud, focus mode), **Aparência** (theme, visualizer, background aurora, labels), **Atenção** (notify when waiting or on errors, and your rules per source and state, next to the defaults and the ones from `config.json`, which win) and **Plugins e pacotes** (what's installed, how each plugin's last run went, and the folders). `config.json` is still where webhooks and fish menu actions go.

**Languages:** the interface texts go through `tr(...)` (Sources/Fishbots/L10n.swift): the Portuguese text is the key and `L10nEnglish.swift` has the English. When adding a text, add its English too; `python3 scripts/l10n-check.py` lists what's missing. A pack's theme can bring its name in both languages with `"names": {"en": "…"}`.

The app icon is drawn by `scripts/make-icon.swift` (`swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`).

## Themes, fish kinds and packs

- **Tema** (**E**, or the menu bar menu and the Aquário menu): a window with every theme's picture, where it comes from and what it brings; click a picture to use it. **Tema surpresa** picks another one by itself every hour or every day. The scene's look: water, light, seaweed, sand, which creatures live there, and the scene's preferred visualizer and music style. Built in: **Aquário** (the original), **Fundo do mar** (dark, few plants, an anglerfish, the sunfish, hammerheads, rusted helms and barnacle-crusted bottles) and **Lagoa** (a coastal lagoon: mangrove roots, seagrass, seahorses, a fishermen's trap and a manatee that comes up to breathe).
- **Tipo de peixe** (in the fish's right-click menu): the project's fish. Automatic follows the session (oval in Rex, elongated in a plain terminal, pufferfish in the Claude app, angelfish in VS Code/Cursor, octopus for GitHub, stingray for Codex); you can pick any kind, including the ones from packs. **Preferências → Geral → Agentes → Peixe de cada agente** picks one for all of an agent's fish (every Codex a stingray, say); a project picked in the menu still wins.
- **Packs** add themes, music styles, fish, scenery and creatures (each drawing in Metal) without compiling anything. They live in `~/Library/Application Support/Fishbots/packs/`; **Tema → Abrir pasta de pacotes…** opens it, and the same menu lists what each pack brought and any problem (a drawing whose Metal doesn't compile is skipped, the rest still loads). Packs are data and GPU code only: they can't run anything on the Mac. Two examples: `packs/examples/coral` (a coral reef, a calm "maré" style and a clownfish) and `packs/examples/koi` (a Japanese pond: koi, a stone lantern, lily pads with lotus, frogs, tadpoles, shrimp and a "zen" style).

```sh
bin/fishbots pack new my-pack                 # start from the template
bin/fishbots pack dev my-pack                 # link it: the aquarium reloads it on every save
bin/fishbots pack preview my-pack             # all its drawings on a sheet, big and at their real size
bin/fishbots pack zip my-pack                 # my-pack.fishbotspack, to share (double-click installs it)
bin/fishbots pack install <file|url>          # or install one someone shared
bin/fishbots skill install                    # teach your coding agent to make packs (and connect agents)
```

A theme can also **dress** what plugins send and the fish its own way (in the Japanese pond a bottle floats as a paper lantern and the plain fish are koi); turn it off in Preferências → Aparência, and a plugin can keep its own drawing with `"override_theme": true`. **Tema → Explorar pacotes…** is the community catalog: install with a click, and the app tells you when a pack you have gets a new version. Sending one is a pull request ([community/README.md](community/README.md)); the catalog's address can be changed with `"catalog": "https://…/index.json"` in `config.json`. A pack whose drawings slow the aquarium down is paused by itself (**Tema → Reativar**).

How to make one, step by step: [docs/packs.md](docs/packs.md). The format is in `Sources/Fishbots/Packs.swift` and the design of all the extension points in [docs/extensions.md](docs/extensions.md).

## Screen saver

```sh
scripts/saver.sh install     # builds build/Fishbots.saver and copies it to ~/Library/Screen Savers
```

Then, in System Settings → Screen Saver, choose **Fishbots**. It's the same engine, without sound. It asks the app (`/state`) who's in the tank and shows the real fish, with name and state; without the app open, just the decorative aquarium.

## How the aquarium sounds

**By default, silence: sound only plays when something changes.** That includes arriving, finishing (a discreet knock-knock on the glass), starting to wait for you (the question and the tap on the glass, with a reminder every 2.5 min) and errors. Working makes no sound, only movement. The **A** key (or the menu) turns on **ambient music**, a piece generated with the ideas of the Jardim de Chuva generator (`Sources/Aquario/Generator.swift`):
- **4 calm styles:** lullaby (kalimba music box), ambient (breath and pad), lo-fi (swung electric piano) and bossa (3+3+2). Each has the garden's progressions, tempo, scale and timbres.
- **Real phrasing, like the garden's `genPhrase`:** the motif of the singing session becomes the "A", and the phrase takes the forms AA'AB, ABAB', ABAC and AABA, with a question in the middle and an answer resolving on a chord tone. The scale adapts to the chord (Fm brings in A♭).
- **One voice at a time:** sessions take turns singing, with breathing room (sometimes nobody sings).
- **Energy:** the more sessions working, the more movement (lullaby → ambient → lo-fi → bossa). The piece changes every ~2–3 min, into a neighboring key, like the garden's radio. The piece's name appears in the footer.

The table below describes each state's signals. The note on each tool use is optional and off by default.

- **Each thing has a motif:** a short, fixed phrase. The motif is chosen from the name (source + label), stored and never changes, so you recognize it by ear.
- **The state changes the motif's "clothes", never its shape:**

| state | fish | sound |
|---|---|---|
| born | drops from above | the motif quickly, rising |
| busy | swims in the middle and up high | the motif every 2 bars; each tool is a short note; the filter pump pulses |
| idle / ok | sinks to the bottom, dimmer | the motif low and quiet every 8 bars |
| waiting | comes to the front of the glass, bigger, glowing | only the start of the motif (a question) and **taps on the glass** |
| error | red, trembling | the motif with the last note a semitone up, dissonant until fixed |
| alert | amber | like error, more spaced out |
| done | comes close to the glass | a discreet knock-knock on the glass, tuned to the motif's first two notes |

- **A session you're already looking at calls without sound:** when its terminal is in front with the focus on its pane (Rex, Herdr, iTerm, or tmux's active pane), waiting and errors skip the motif, the taps and the question read aloud. The fish still comes to the glass and changes color, and the notification still arrives. In Rex, a pane counts as focused in its session even when the Rex window shows another session. Ghostty, Terminal and the rest always call.
- The jellyfish plays the chords (D pentatonic, changing every 2 bars). Events become food and an arpeggio. A full disk makes the water cloudy and the sound muffled.

## Protocol

Everything comes in through `POST http://127.0.0.1:7777/event` (local only) with an object or a list:

```json
{"source":"x","entity":"id","state":"busy","label":"name"}   // entity = fish
{"source":"x","entity":"id","state":"end"}                   // leaves the aquarium
{"source":"x","entity":"id","tool":"Bash"}                   // activity pulse
{"source":"x","event":"deploy","label":"meu-site"}           // event = food
{"source":"x","gauge":"disk","value":0.87}                   // gauge 0…1
{"source":"x","effect":"fireworks","label":"deploy"}         // effect: fireworks, lightning, quake, school…
{"source":"x","presence":"prod","kind":"shark","state":"error","label":"prod","detail":"3 pods em CrashLoop"}
```

**Effects and presences** change the aquarium itself, not just the fish: an effect is a one-off moment (fireworks, lightning, a quake, a school crossing, a shooting star…), and a presence is a creature or object a plugin keeps in the tank (shark, submarine, turtle, jellyfish, seahorse, crab, starfish, bottle, hourglass, anchor, flag, chest, battery) with a state, a label, a detail and a link. The full list, the states and how the text shows are in [docs/scene.md](docs/scene.md).

States: `born busy idle waiting ok alert error done` (+ `end`). `GET /state` returns the aquarium as JSON. Packs:
`GET /packs` (what's installed and its problems), `POST /packs/reload`, `POST /packs/install` (`{"path": "…/x.fishbotspack"}`).

From the command line (`bin/fishbots`):

```sh
fishbots state ci build-42 busy "CI meu-site"
fishbots state ci build-42 error
fishbots event github deploy "meu-site → main"
fishbots gauge mac cpu 0.4
fishbots effect ci fireworks "deploy meu-site"
fishbots presence k8s prod shark error prod "3 pods em CrashLoop"
fishbots presence k8s prod end
fishbots show
```

A session can also command the others (off until you turn on "Sessions can command other sessions" in Settings →
General), which is what an orchestrating agent needs ([docs/extensions.md](docs/extensions.md), point 11;
`fishbots skill install` teaches your agent the cycle):

```sh
fishbots spawn --cwd ../api "implement X; when done, sum it up"   # a new session in a new tab (Rex, Herdr, tmux), as this one's child
fishbots wait claude-code:1f3a codex:9b2c     # until one is done, waiting or error: which, and its last reply
fishbots reply claude-code:1f3a "use the new table"
fishbots stop claude-code:1f3a
```

## Plugins

### Claude Code

`plugins/claude-code/hook.sh` forwards the hooks' JSON to `POST /claude-code`, and the aquarium translates:

- `SessionStart` → born
- `UserPromptSubmit` → busy
- `PreToolUse` → busy + tool note
- `PermissionRequest`/`Notification` → waiting
- `Stop` → done
- `PreCompact` → compacting; compact `SessionStart` → end of compaction
- `SessionEnd` → leaves

The label is the session's folder. To enable it, run `scripts/install-hooks.sh claude-code` (it merges `plugins/claude-code/hooks.json` into `~/.claude/settings.json`, or the settings file you pass, pointing at wherever you cloned this, with a backup). The hook never blocks the session: it has a 1 s timeout and always exits with 0.

### Click a fish: go to it

The hook also sends **where** the session is (`X-Where-*` headers). The label gets a 2nd line with that, and clicking the fish takes you there (clicking empty water still feeds):

- **Rex:** shows `session › tab` and, on click, the app selects the session and tab and focuses the exact pane (`session.select` + `block focus`).
- **Rex without the variables:** if the session arrived without `REX_*`, the aquarium looks up the pane by Claude's pid and the tty's processes.
- **Rex, in its own words:** a session in a Rex pane says what it's doing (Claude Code reports it to the terminal, and Rex passes it on: `program_status_changed`). The fish shows that line for a few seconds instead of the tool's name ("Running the tests" rather than "Bash"), the full label keeps it while it works, and the card has it under the title. The pane's title and its place (session › tab › pane) come the same way, when they change: the aquarium listens to Rex (`rex events`, one stream for the server and one per session) instead of asking it every few seconds.
- **Programs without hooks (Rex and Herdr):** anything that reports its status to its terminal (the Program Status Protocol, OSC 7501: a build, a deploy, a script of yours; `printf '\e]7501;state=working:app=my-build:msg=%s\e\\' "$(printf 'Compiling' | base64)"`) becomes a fish by itself in a Rex pane or a Herdr terminal, named after the program: busy while it works (with its line of text), waiting when it's blocked on you (its line is the question), done, error. It leaves when the program takes its status back, exits, or the terminal closes; clicking it goes there. Agents the aquarium already knows by their hooks don't get a second fish. `config.json` picks which programs, per multiplexer: `{"rex": {"only": ["cargo"], "ignore": ["terraform"]}}`, or `"herdr": false` for none.
- **No known terminal:** the hook walks up the parent processes to the `.app` that opened the session (e.g. ClaudeCode.app), shows its name in the label, and the click brings that app forward.
- **Herdr:** shows `Herdr · space › tab` (from `herdr-core`) and, on click, shows the agent in the Herdr window (`herdr-app do agent.focus`). Reply and Esc from the card go through `herdr-core send`/`keys`, after checking the agent is still in front.
- **Herdr, by itself:** like Rex, Herdr is listened to (`herdr-core events`): what a session says it's doing, its title and its place (space › tab) arrive when they change, and programs that report their status become fish. The stream opens only when Herdr's core is already running; the aquarium never starts it.
- **Ghostty (1.3+):** the click finds the session's own terminal through Ghostty's AppleScript, by tty (or by folder and title on older dictionaries); reply and Esc from the card work too, after checking the terminal's foreground process is the agent. macOS asks once for permission to control Ghostty.
- **Editors:** Cursor, Windsurf and other VS Code forks say `TERM_PROGRAM=vscode`; the label and the click use the app the session really runs in. Zed opens on the session's folder.
- **Without Rex:** a generic script handles iTerm (by session), Terminal (by tty), tmux (by pane), WezTerm, kitty, Ghostty, Warp (the app only: it can't be told which tab), VS Code and its forks, and Zed. To replace it with your own, create `~/Library/Application Support/Fishbots/goto.sh`. It receives `WHERE_TERM`, `WHERE_ITERM`, `WHERE_TTY`, `WHERE_TMUX`, `WHERE_WEZTERM`, `WHERE_KITTY`, `WHERE_CWD`, `WHERE_APP`, `WHERE_PID` and `WHERE_TITLE` (the conversation's title).

The **fish menu** (right-click) has: go there, open the folder, copy the path, **change motif** (hovering over the options plays each one), mute the project and remove from the aquarium. Sessions from the same project share a motif, but with different pitch and size.

Other plugins can send, on the entity, `"link"` (a URL opened on click), `"detail"` (the 2nd line) or `"where"` (the same object as above).

### Attention

Each `source:state` has a level:
- **ambient:** color and music only;
- **attention:** taps on the glass, and the error turns dissonant;
- **urgent:** on top of that, a macOS notification (clicking it goes to the fish), bouncing Dock icon and badge.

The default is `*:waiting` and `*:error` at attention, and `github:error` at ambient. The **Aquário** menu (the aquarium menu in the menu bar) turns on waiting and error notifications, and **Abrir configuração de atenção…** ("open attention settings") creates `~/Library/Application Support/Fishbots/config.json`:

```json
{"attention": {"claude-code:waiting": "urgent", "github:*": "ambient"}}
```

**Focus mode** (**S**) silences the background music, and only what needs attention plays.

### Webhooks and menu actions

`config.json` (the same file as the attention rules) can also send what happens to a URL and add items to the fish menu:

```json
{
  "webhooks": [{"url": "https://example.com/hook", "types": ["state", "permission"], "states": ["waiting", "error", "done"]}],
  "actions": [{"title": "Abrir no Cursor", "command": ["/usr/bin/open", "-a", "Cursor", "{cwd}"]}]
}
```

Each webhook gets a JSON POST per event (`type` state, permission or party, plus `source`, `entity`, `label`, `state`, `previous`, `title`, `detail`, `time`); `types` and `states` filter (leave them out for everything). Actions run without a shell, with `{cwd}`, `{link}`, `{label}`, `{source}`, `{entity}` and `{title}` replaced, and only show on fish that have every value they use.

### Script plugins (xbar style)

Executables in `~/Library/Application Support/Fishbots/plugins/`, where each stdout line is a protocol JSON:
- `name.5m.sh` runs every 5 min (accepts `s`, `m`, `h`, `d`). Entities that disappear from one run to the next leave the aquarium, but only if the run succeeded.
- `name.sh` (no interval) keeps running, and is restarted if it exits.

The **Plugins** menu shows each one's state; click one to open its log (`~/Library/Logs/Fishbots/plugins/<name>.log`): every run with its exit code and whole stderr, a continuous plugin's stderr as it comes, and every output line the aquarium refused, with why (`line 2: unknown state: workin · {…}`). A plugin whose lines are refused shows ✗ even when it exits with 0. From the terminal: `bin/fishbots plugin log <name>`. Examples in `plugins/examples/`:
- **github:** your PRs by CI and reviews requested from you (waiting); clicking opens the PR.
- **mac:** CPU and battery. The battery becomes an old battery lying in the sand, with its charge in bars, glowing when plugged in.
- **k8s:** every kubectl context becomes a small light on the side glass (docs/scene.md), in the state's color: green when healthy, breathing blue while Flux reconciles, amber with pods in CrashLoopBackOff/ImagePullBackOff, red when a Kustomization or HelmRelease fails, gray when it can't be reached. A healthy one stays quiet; one in trouble grows and says why, and a click lists them all. `FISHBOTS_K8S_HELMS` names the clusters you'd rather see as a ship's wheel fallen on the sand. A shark patrols while some cluster is broken; a cluster that recovers sets off fireworks, one that breaks a lightning. Read-only (`kubectl get`); `FISHBOTS_K8S_CONTEXTS` picks the clusters and `FISHBOTS_K8S_TRIM` shortens their names.
- **uptime:** wraps a StatusCake SwiftBar/xbar plugin (`FISHBOTS_UPTIME_CMD`; it doesn't hold an API key itself): a flag with ▲ up ▼ down, a bottle for each test that is down (click: the test), a shark while a Critical test is down, lightning when a test goes down and fireworks when it comes back.
- **weather:** the real weather drives the scene (Open-Meteo, no key): rain, wind as waves, warm or cold water, fog; a jellyfish shows the temperature and the sky, and a thunderstorm sends lightning. Set `FISHBOTS_WEATHER_CITY` (or `_LAT`/`_LON`) in `plugins.env`.

Personal settings for the plugins (paths, cluster lists, anything with your names in it) go in `~/Library/Application Support/Fishbots/plugins.env`, a shell file the plugins read if it exists (the app doesn't run it: it isn't executable). It stays out of the repository.
- **example:** a template.

```sh
scripts/plugins.sh install github mac
scripts/plugins.sh remove github
```

### Answering permissions from the aquarium

When a session asks for permission, the fish comes to the glass with **"✋ quer usar Bash · clique para responder"** ("wants to use Bash · click to answer"). Clicking opens the request (the command, file, URL) with **Permitir / Negar / Ir até lá** ("allow / deny / go there"). The same options are in the menu bar 🐠 and, if waiting is set to urgent, in the notification buttons. The request keeps showing in the terminal at the same time, and whoever answers first wins; answer it there and the aquarium's request closes by itself.

Since the hook can approve tools on your behalf, it isn't enabled by default. Install it yourself:

```sh
scripts/install-permission.sh ~/.claude/settings.json      # or: scripts/install-hooks.sh claude-code --permission
```

AskUserQuestion and ExitPlanMode become "waiting" (with "Ir até lá"), but aren't answered by the aquarium: answering would require holding PreToolUse, and then the question would only show up in the terminal afterwards.

### Codex

Codex has hooks in the same format. Its sessions become **rays**, and the aquarium reads the Codex conversation (`~/.codex/sessions/…/rollout-*.jsonl`): the title comes from `thread_name` in `~/.codex/session_index.jsonl`, the branch from `session_meta` and the context fat from the last `token_count`, using the model's real limit (`model_context_window`). The hooks are in `plugins/codex/hooks.json` (routes `/codex` and `/codex/permission`); `scripts/install-hooks.sh codex` merges them into `~/.codex/hooks.json`. Codex asks you to trust each new hook.

### Cursor

Cursor's agent (the app's chat and `cursor-agent`) has its own hooks, which `plugins/cursor/hook.sh` forwards to `POST /cursor`. Its sessions become **angelfish**, labeled with the workspace folder: prompt → busy, tools → busy with their animation (`Shell` puffs bubbles, `StrReplace` nibbles), subagents → fry, compaction, and at the end the last response goes on the card (ending in a question → waiting; stopped by you → idle). Not yet: the context fat (Cursor sends the tokens of the whole turn, not the context size), its questions (`AskQuestion` sends no hook) and answering permissions. Reply and Esc work only for `cursor-agent` in Rex, iTerm or tmux. `scripts/install-hooks.sh cursor` merges `plugins/cursor/hooks.json` into `~/.cursor/hooks.json`. For now the hook also logs every event to `~/Library/Logs/Fishbots/cursor-events.jsonl`.

### Antigravity

Antigravity (Google's successor to Gemini CLI: the CLI `agy`, its IDE and its app) reads hooks from `~/.gemini/config/hooks.json`, shared by all three; `scripts/install-hooks.sh antigravity` adds a `fishbots` entry there. Its payload doesn't name its event, so each event calls `plugins/antigravity/hook.sh <Event>`, which forwards to `POST /antigravity`: `SessionStart` → born, `PreInvocation` → busy (the first prompt names the conversation), `PostToolUse` → the tool's animation (`run_command` puffs bubbles, `replace_file_content` nibbles), `Stop` → done (or error). It stays out of `PreToolUse` on purpose: there a hook must decide, and one that fails blocks the tool. Not yet: waiting for you (Antigravity has no permission event) and the reply on the card (it's only in an undocumented transcript). Antigravity cleans the hook's environment, so the terminal is found through the parent processes (tty, Rex), not iTerm/tmux/Herdr variables. Written from Antigravity's hook docs and not yet tried on a real session; the last event is kept in `~/Library/Logs/Fishbots/antigravity-last.json`.

### Gemini CLI (retired)

Gemini CLI stopped serving most users on June 18, 2026 (Antigravity replaces it). Its hooks (`hooks` in `~/.gemini/settings.json`) go through `plugins/gemini/hook.sh` to `POST /gemini`. Its events and tool names are translated to Claude Code's (`BeforeAgent` → prompt, `BeforeTool`/`AfterTool` → tools, `run_shell_command` puffs bubbles, `replace` nibbles; `Notification` → waiting for a permission; `AfterAgent` → the reply on the card). `scripts/install-hooks.sh gemini` merges `plugins/gemini/hooks.json` into `~/.gemini/settings.json`. Written from Gemini CLI's hook reference and not yet tried on a real session; its last event is kept in `~/Library/Logs/Fishbots/gemini-last.json` to check the format. Reply and Esc need the terminal to show the `gemini` process in front (it runs on node, so not always).

### opencode

opencode loads plugins from `~/.config/opencode/plugins/`; `scripts/install-hooks.sh opencode` links `plugins/opencode/fishbots.js` there. The plugin turns opencode's events (`session.created`/`updated`/`idle`/`error`, user messages, `tool.execute.before`/`after`, permissions) into Claude Code's hook shape and posts them to `POST /agent/opencode` (an agent without Swift, below), with the session's title and where it runs. Subagent sessions don't become fish of their own (their parent shows fry). Written from opencode's plugin docs (the function-export API) and not yet tried on a real session.

### Your own agent

Any agent with hooks can join without touching the app: have its hook (or plugin) post Claude Code-shaped events to `POST /agent/<id>` — `hook_event_name` (SessionStart, UserPromptSubmit, PreToolUse with `tool_name`/`tool_input`, PostToolUse, Notification, Stop with `last_assistant_message`, StopFailure, SessionEnd…), `session_id`, `cwd` and optionally `session_title`. `plugins/common/hook.sh <route>` forwards a hook's stdin with the `X-Where-*` headers, so the click and reply/Esc find its terminal. Optionally, describe it in `~/Library/Application Support/Fishbots/agents/<id>.json` (read when the app opens; after changing it, Preferences → Agents → Reload, or `POST /agents/reload`):

```json
{"id": "aider", "name": "Aider", "processNames": ["aider"], "fish": "slender", "timbre": "pluck",
 "events": {"turn_start": "UserPromptSubmit"}, "tools": {"run_command": "Bash"}}
```

The maps rename its events and tools to Claude Code's, so a hook that already sends JSON in its own words may need no translation at all. To try it:

```sh
bin/fishbots agent new aider "Aider"          # a starting manifest
bin/fishbots agent reload                     # after changing a manifest (or Preferences → General → Agents → Reload)
bin/fishbots agent test aider                 # a fake session: prompt, tools, a reply, the end
bin/fishbots agent list                       # every agent (built in, /agent/<id>) and manifest problems
```

The whole guide: [docs/agents.md](docs/agents.md). `bin/fishbots skill install` also teaches your coding agent to do it (the `fishbots-agents` skill).

### MCP, lists and skills

- **MCP tool:** a seahorse comes in from the side with a little letter in the server's color; the fish goes to meet it, and the label shows "mcp · server".
- **TodoWrite:** the list becomes pebbles in the sand, and the finished ones glow in the fish's color.
- **Skill:** a ring of sparkles around the fish.

### While you were away

The aquarium logs what happens: finished tasks, errors, who was left waiting, merged PRs and deploys. After 10 min without touching the Mac, it marks you as away; when you come back, the button **"🌙 Enquanto você estava fora · 1h20"** ("while you were away") appears at the top (also in the menu bar 🐠). Clicking opens a card with the summary and runs a **parade**: each fish that did something comes to the front of the glass, one at a time, and the period's pearls light up in sequence. The **R** key (or the menu) shows the summary of the last 2 hours at any time.

### Mac (built in)

Disk usage every minute (`mac:disk`).

See `ROADMAP.md` for next steps.
