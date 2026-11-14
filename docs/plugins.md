# Plugins and protocol

Anything that can send a line of JSON can put a fish, a creature or an effect in the tank: a CI build, a cluster, your PRs, the weather.

## The protocol

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

**Effects and presences** change the aquarium itself, not just the fish: an effect is a one-off moment (fireworks, lightning, a quake, a school crossing, a shooting star…), and a presence is a creature or object a plugin keeps in the tank (shark, submarine, turtle, jellyfish, seahorse, crab, starfish, bottle, hourglass, anchor, flag, chest, battery) with a state, a label, a detail and a link. The full list, the states and how the text shows are in [docs/scene.md](scene.md).

States: `born busy idle waiting ok alert error done` (+ `end`). `GET /state` returns the aquarium as JSON, `GET /journal` what happened today (`?hours=N`: in the last hours). Packs:
`GET /packs` (what's installed and its problems), `POST /packs/reload`, `POST /packs/install` (`{"path": "…/x.fishbotspack"}`).

## From the command line

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

Other plugins can send, on the entity, `"link"` (a URL opened on click), `"detail"` (the 2nd line) or `"where"` (the same object as above).

## Attention

Each `source:state` has a level:
- **ambient:** color and music only;
- **attention:** taps on the glass, and the error turns dissonant;
- **urgent:** on top of that, a macOS notification (clicking it goes to the fish), bouncing Dock icon and badge.

The default is `*:waiting` and `*:error` at attention, and `github:error` at ambient. The **Aquário** menu (the aquarium menu in the menu bar) turns on waiting and error notifications, and **Abrir configuração de atenção…** ("open attention settings") creates `~/Library/Application Support/Fishbots/config.json`:

```json
{"attention": {"claude-code:waiting": "urgent", "github:*": "ambient"}}
```

**Focus mode** (**S**) silences the background music, and only what needs attention plays. It also turns on by itself while a macOS Focus is on (Do Not Disturb, Work, Sleep…, by hand or on a schedule) and off when that Focus ends, unless you had turned it on yourself (Preferências → Atenção).

## Webhooks and menu actions

`config.json` (the same file as the attention rules) can also send what happens to a URL and add items to the fish menu:

```json
{
  "webhooks": [{"url": "https://example.com/hook", "types": ["state", "permission"], "states": ["waiting", "error", "done"]}],
  "actions": [{"title": "Abrir no Cursor", "command": ["/usr/bin/open", "-a", "Cursor", "{cwd}"]}]
}
```

Each webhook gets a JSON POST per event (`type` state, permission or party, plus `source`, `entity`, `label`, `state`, `previous`, `title`, `detail`, `time`); `types` and `states` filter (leave them out for everything). Actions run without a shell, with `{cwd}`, `{link}`, `{label}`, `{source}`, `{entity}` and `{title}` replaced, and only show on fish that have every value they use.

## Script plugins (xbar style)

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

## Mac (built in)

Disk usage every minute (`mac:disk`).
