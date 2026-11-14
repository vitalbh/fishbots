# Using the aquarium

Everything you can do with the tank, its fish and its cards. The short version is in the [README](../README.md).

## Keys and gestures

Keys and shortcuts:
- **Click a fish:** go to it. **Right-click:** fish menu. **Click empty water:** feed.
- **The card's step trail:** what the session has been doing, drawn — its latest steps as beads on a line toward "now", each with an icon and a color for its kind (reading, searching, editing, running a command, the web, a sub-agent, its list, what you told it); while it works a light runs along the line and the current step breathes, and a new step pops in. Hover a bead for its time and what the session said about it; "see the history" lists them in words.
- **Tab / ⇧Tab** (aquarium in front): goes through the sessions, the ones waiting for you first, opening each card with its reply field ready (type, Enter sends). On the chosen card: **⌘↩** go there, **⌘R** hear the question, **⌘D** speak the reply, **A / N** allow or deny a permission request, **Esc** close. The card's footer lists only the keys that fish takes.
- **Global shortcuts** (any app, set in Preferências → Geral): **⌃⌥F** go to whoever has waited longest, **⌃⌥R** hear their question, **⌃⌥M** reply by voice, **⌃⌥A** talk to the aquarium's assistant.
- **Click a pearl:** what was done around that time. The day's pearls are a timeline on the sand, from the morning (left) to now (right).
- **Drag a fish:** it's pulled along a little and swims back when you let go. **Drag through the water:** a short current (snow, seaweed and fish go with it). **Double-click the water:** a knock on the glass, and the idle fish and the schools come to look. **Scroll over the water:** sprinkles food.
- **D** demo · **M** sound · **S** focus mode · **T** float above windows · **F** food · **W** widget mode (see below). W again to come back.
- **L** cycles the labels: **minimal** (default: the short title, or the name, plus a second line only when it matters: whenever it needs you, and for a few seconds when something happens), **full** or **none**. Everything else is in the hover card.
- Closing the window doesn't quit: the aquarium stays in the **menu bar** (🐠, with whoever is waiting for you).

## Widget mode

**Widget mode (W):** the aquarium moves into the Mac's notch, or into a notch drawn at the top of another monitor (hidden while an app is full screen there), always on top and on every Space; the app comes back in it after a restart.
- **Closed:** on the left, a fish per working session (up to three, in each one's color) and how many work, or the album's cover (and the song on the right) while music plays and nobody works; a thin light runs along the bottom while anyone works. On the right, who needs you, a session or a plugin's presence (✋, or ✕ for an error) and for how long, with what it asked and its latest steps (the step trail, below) showing under the name when the mouse rests on it, a 🎙 to answer by voice, with **Allow / Deny** or a short question's answers right there; back from a while away, what happened meanwhile (a click opens the summary); for a few seconds, ✓ who just finished; otherwise, dim, who has been working longest (its steps show under it too, and a click goes to it). On the Mac's own notch the right side only shows the count until the mouse is over it, so it stays off the menu bar's icons. Someone new needing you makes the strip pulse.
- **Click the name** to go to that session's terminal (a presence: its link). **+** (on hover) starts a new session. **Drop files or text** on the strip to send them to a session as a reply (a menu picks which, who's waiting first). **Mouse over** (or a click, in Preferences) opens a small tank below the notch, with a band under the strip showing the steps of who needs you (or of who has been working longest) live, and showing only who needs you, in calm water (no schools, visitors, pearls or visualizer; at most three presences, the rest counted on the strip); clicking the strip also takes the keyboard (**Tab** through who's waiting, **Enter** to their terminal, **Esc** closes and gives the keyboard back).
- **Right-click** the strip: focus mode, silence for an hour, animations on/off (off by default with macOS's Reduce motion), where the widget goes, back to the window.
- Preferences → Appearance → Widget: the monitor (or the old little window in the corner, where dragging the water moves it), opening with the mouse or a click, and the open size.

## The living aquarium

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

**MCP, lists and skills:**

- **MCP tool:** a seahorse comes in from the side with a little letter in the server's color; the fish goes to meet it, and the label shows "mcp · server".
- **TodoWrite:** the list becomes pebbles in the sand, and the finished ones glow in the fish's color.
- **Skill:** a ring of sparkles around the fish.

To see it all in action: `open --env FISHBOTS_FAST=1 build/Fishbots.app` (shortens the timings) and `scripts/tour.sh`, which stages each mechanic with test fish and tells you in the terminal what to look at.

## The fish menu

The **fish menu** (right-click) has: go there, open the folder, copy the path, **change motif** (hovering over the options plays each one), mute the project and remove from the aquarium. Sessions from the same project share a motif, but with different pitch and size.

Other plugins can send, on the entity, `"link"` (a URL opened on click), `"detail"` (the 2nd line) or `"where"` (the same object as above).

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

## Themes and packs

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

A theme can also **dress** what plugins send and the fish its own way (in the Japanese pond a bottle floats as a paper lantern and the plain fish are koi); turn it off in Preferências → Aparência, and a plugin can keep its own drawing with `"override_theme": true`. **Tema → Explorar pacotes…** is the community catalog: install with a click, and the app tells you when a pack you have gets a new version. Sending one is a pull request ([community/README.md](../community/README.md)); the catalog's address can be changed with `"catalog": "https://…/index.json"` in `config.json`. A pack whose drawings slow the aquarium down is paused by itself (**Tema → Reativar**).

How to make one, step by step: [docs/packs.md](packs.md). The format is in `Sources/Fishbots/Packs.swift` and the design of all the extension points in [docs/extensions.md](extensions.md).

## The resident assistant

A moray lives in a burrow on the sand: the aquarium's own assistant. Click it (or **⌃⌥A** from any app: its card opens with the microphone on, and what you say is sent when you stop talking) and ask about the aquarium: who's waiting for you, what happened today, what each session is doing. Ask it to answer, stop or start a session, or to remember something. Its answer shows on the card as it's written and can be read aloud; the fish it names light up, and the card has a way to each.

- **The app has no model in it.** What thinks is the agent you already have (Claude Code or Codex), run by the aquarium in the background, on your account and with the connectors it already has. Preferências → Assistente picks which one and the model (Claude Code answers on its small model unless you say otherwise), or any command of yours that takes the question on its input and writes the answer to its output.
- **It sleeps between conversations:** nothing runs until you talk to it. The process stays for five minutes after the last answer (the next one comes in about a second), then goes; the conversation is resumed when needed and starts over each day.
- **What it knows:** each question goes with the sessions in the tank and the day's journal (`GET /journal`, `fishbots journal`: kept on disk now, so it's still there after reopening the app). What it remembers between conversations is `notes.md` in its own folder (`~/Library/Application Support/Fishbots/assistant`, with its instructions and the aquarium's skills), which it reads and writes and so can you.
- **What it may do:** looking at the aquarium and writing its own notes need no asking. Anything else its agent would ask about shows on the card (**Permitir**, **Sempre**, **Negar**), and the moray comes out of its burrow and waits; what you mark as *Sempre* is listed in Preferences, where it can be removed. The permissions the agent already has in its own settings still apply. It acts on sessions through the `fishbots` command, like any session that leads others (it needs "Sessions can command other sessions"). Codex has no one to ask in the background: it works inside its sandbox.
- **"Always", as wide as you want:** for a shell command the card offers the command (`rex send …`) or the whole program (`rex`); for a connector's tool, the tool or the whole connector. Preferences → Assistente lists the rules, removes them and takes one written by hand. A command with pipes or redirections is asked every time.
- **It tells you later:** ask it to let you know when a session finishes or what it answers, and it watches that session (`fishbots watch <fish> [what you want to know]`); when the session stops, the app wakes the assistant with its reply, and the moray comes out of its burrow with the news (read aloud, if you turned that on).
- **Open in the terminal** (on the card, where Rex, Herdr, iTerm or tmux can open one) goes on with the same conversation in a pane, to see everything it does.
- Its sessions don't become fish: it's the creature in the burrow. `moray` is also a kind of presence plugins can use (docs/scene.md), and a theme can dress it.

## While you were away

The aquarium logs what happens: finished tasks, errors, who was left waiting, merged PRs and deploys. After 10 min without touching the Mac, it marks you as away; when you come back, the button **"🌙 Enquanto você estava fora · 1h20"** ("while you were away") appears at the top (also in the menu bar 🐠). Clicking opens a card with the summary and runs a **parade**: each fish that did something comes to the front of the glass, one at a time, and the period's pearls light up in sequence. The **R** key (or the menu) shows the summary of the last 2 hours at any time.

## Preferences

**Preferências…** (⌘, or the menu bar menu) has five tabs (the fifth, **Assistente**, is the resident assistant's: who thinks for it, its voice, what it may do without asking, its notes): **Geral** (open at login, menu bar only, floating, other devices, sound and volume, ambient music, a note per tool, reading questions aloud, focus mode), **Aparência** (theme, visualizer, background aurora, labels), **Atenção** (notify when waiting or on errors, and your rules per source and state, next to the defaults and the ones from `config.json`, which win) and **Plugins e pacotes** (what's installed, how each plugin's last run went, and the folders). `config.json` is still where webhooks and fish menu actions go.

## Screen saver

```sh
scripts/saver.sh install     # builds build/Fishbots.saver and copies it to ~/Library/Screen Savers
```

Then, in System Settings → Screen Saver, choose **Fishbots**. It's the same engine, without sound. It asks the app (`/state`) who's in the tank and shows the real fish, with name and state; without the app open, just the decorative aquarium.
