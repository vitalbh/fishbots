# Agents and terminals

The agents Fishbots knows out of the box, how a click on a fish finds the session's terminal, and how to connect any other agent.

## Claude Code

`plugins/claude-code/hook.sh` forwards the hooks' JSON to `POST /claude-code`, and the aquarium translates:

- `SessionStart` → born
- `UserPromptSubmit` → busy
- `PreToolUse` → busy + tool note
- `PermissionRequest`/`Notification` → waiting
- `Stop` → done
- `PreCompact` → compacting; compact `SessionStart` → end of compaction
- `SessionEnd` → leaves

The label is the session's folder. To enable it, run `scripts/install-hooks.sh claude-code` (it merges `plugins/claude-code/hooks.json` into `~/.claude/settings.json`, or the settings file you pass, pointing at wherever you cloned this, with a backup). The hook never blocks the session: it has a 1 s timeout and always exits with 0.

## Answering permissions from the aquarium

When a session asks for permission, the fish comes to the glass with **"✋ quer usar Bash · clique para responder"** ("wants to use Bash · click to answer"). Clicking opens the request (the command, file, URL) with **Permitir / Negar / Ir até lá** ("allow / deny / go there"). The same options are in the menu bar 🐠 and, if waiting is set to urgent, in the notification buttons. The request keeps showing in the terminal at the same time, and whoever answers first wins; answer it there and the aquarium's request closes by itself.

Since the hook can approve tools on your behalf, it isn't enabled by default. Install it yourself:

```sh
scripts/install-permission.sh ~/.claude/settings.json      # or: scripts/install-hooks.sh claude-code --permission
```

AskUserQuestion is answered on the card: its answers are buttons, with a field for an answer in your own words (several questions make a form; "Responder no terminal" shows the terminal's menu instead). ExitPlanMode becomes "waiting" and is answered in the terminal. Every session's card has "↗ ir para o painel" (or "a sessão") at the bottom, which takes you there.

## Click a fish: go to it

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

## Codex

Codex has hooks in the same format. Its sessions become **rays**, and the aquarium reads the Codex conversation (`~/.codex/sessions/…/rollout-*.jsonl`): the title comes from `thread_name` in `~/.codex/session_index.jsonl`, the branch from `session_meta` and the context fat from the last `token_count`, using the model's real limit (`model_context_window`). The hooks are in `plugins/codex/hooks.json` (routes `/codex` and `/codex/permission`); `scripts/install-hooks.sh codex` merges them into `~/.codex/hooks.json`. Codex asks you to trust each new hook.

## Cursor

Cursor's agent (the app's chat and `cursor-agent`) has its own hooks, which `plugins/cursor/hook.sh` forwards to `POST /cursor`. Its sessions become **angelfish**, labeled with the workspace folder: prompt → busy, tools → busy with their animation (`Shell` puffs bubbles, `StrReplace` nibbles), subagents → fry, compaction, and at the end the last response goes on the card (ending in a question → waiting; stopped by you → idle). Not yet: the context fat (Cursor sends the tokens of the whole turn, not the context size), its questions (`AskQuestion` sends no hook) and answering permissions. Reply and Esc work only for `cursor-agent` in Rex, iTerm or tmux. `scripts/install-hooks.sh cursor` merges `plugins/cursor/hooks.json` into `~/.cursor/hooks.json`. For now the hook also logs every event to `~/Library/Logs/Fishbots/cursor-events.jsonl`.

## Antigravity

Antigravity (Google's successor to Gemini CLI: the CLI `agy`, its IDE and its app) reads hooks from `~/.gemini/config/hooks.json`, shared by all three; `scripts/install-hooks.sh antigravity` adds a `fishbots` entry there. Its payload doesn't name its event, so each event calls `plugins/antigravity/hook.sh <Event>`, which forwards to `POST /antigravity`: `SessionStart` → born, `PreInvocation` → busy (the first prompt names the conversation), `PostToolUse` → the tool's animation (`run_command` puffs bubbles, `replace_file_content` nibbles), `Stop` → done (or error). It stays out of `PreToolUse` on purpose: there a hook must decide, and one that fails blocks the tool. Not yet: waiting for you (Antigravity has no permission event) and the reply on the card (it's only in an undocumented transcript). Antigravity cleans the hook's environment, so the terminal is found through the parent processes (tty, Rex), not iTerm/tmux/Herdr variables. Written from Antigravity's hook docs and not yet tried on a real session; the last event is kept in `~/Library/Logs/Fishbots/antigravity-last.json`.

## Gemini CLI (retired)

Gemini CLI stopped serving most users on June 18, 2026 (Antigravity replaces it). Its hooks (`hooks` in `~/.gemini/settings.json`) go through `plugins/gemini/hook.sh` to `POST /gemini`. Its events and tool names are translated to Claude Code's (`BeforeAgent` → prompt, `BeforeTool`/`AfterTool` → tools, `run_shell_command` puffs bubbles, `replace` nibbles; `Notification` → waiting for a permission; `AfterAgent` → the reply on the card). `scripts/install-hooks.sh gemini` merges `plugins/gemini/hooks.json` into `~/.gemini/settings.json`. Written from Gemini CLI's hook reference and not yet tried on a real session; its last event is kept in `~/Library/Logs/Fishbots/gemini-last.json` to check the format. Reply and Esc need the terminal to show the `gemini` process in front (it runs on node, so not always).

## opencode

opencode loads plugins from `~/.config/opencode/plugins/`; `scripts/install-hooks.sh opencode` links `plugins/opencode/fishbots.js` there. The plugin turns opencode's events (`session.created`/`updated`/`idle`/`error`, user messages, `tool.execute.before`/`after`, permissions) into Claude Code's hook shape and posts them to `POST /agent/opencode` (an agent without Swift, below), with the session's title and where it runs. Subagent sessions don't become fish of their own (their parent shows fry). Written from opencode's plugin docs (the function-export API) and not yet tried on a real session.

## Connecting another agent

Any coding agent with hooks (or plugins) can live in the aquarium without changing the app: its hook posts events
to `POST /agent/<id>`, and every session becomes a full agent fish. Claude Code, Codex, Cursor, Gemini CLI and
Antigravity are built in; opencode joins this way (`plugins/opencode/fishbots.js`), and it's the reference.

### What the agent gets

- A fish per session, labeled with its folder; the conversation's title on the card.
- Busy while it works, an animation per tool (Bash puffs bubbles, Edit nibbles the seaweed, Read, Grep, WebFetch…),
  fry for subagents (`Task`), pebbles for a todo list (`TodoWrite`), a seahorse for MCP tools (`mcp__server__tool`).
- Waiting when it asks you something, done with its last reply on the card (waiting if the reply ends in a question).
- The 2nd line says where it runs (Rex, Herdr, Ghostty, iTerm, Terminal, tmux, Warp, Cursor…); clicking the fish takes
  you there.
- Reply and Esc from the card, typed into its exact terminal (Rex, Herdr, Ghostty, iTerm, tmux), only after checking
  the agent is the process in front.

### 1. The events

JSON in Claude Code's hook shape, one per POST:

| `hook_event_name` | what it does | fields |
|---|---|---|
| `SessionStart` | a new fish | |
| `UserPromptSubmit` | busy | |
| `PreToolUse` | busy + the tool's animation | `tool_name`, `tool_input` (object) |
| `PostToolUse` | busy | |
| `Notification` | waiting (a `message` with "permission" or "approve"); "waiting for your input" → idle | `message` |
| `Stop` | done (waiting if the reply ends in a question) | `last_assistant_message` |
| `StopFailure` | error | |
| `PreCompact` | compacting (bubbles) | |
| `SubagentStop` | a fry leaves | |
| `SessionEnd` | the fish leaves | |

Every event carries `session_id` (stable for the conversation) and `cwd` (its folder: the fish's label). Optional:
`session_title` (the conversation's name; it wins over the terminal's title). Tool names are Claude Code's (`Bash`,
`Edit`, `Write`, `Read`, `Grep`, `Glob`, `WebFetch`, `WebSearch`, `Task`, `TodoWrite`, `AskUserQuestion`…); the
manifest can map the agent's own names.

### 2. The hook

If the agent runs shell commands as hooks with the event's JSON on stdin, point them at the shared hook:

```sh
plugins/common/hook.sh agent/<id> '<glob of the agent's executable>'
```

It forwards stdin to `POST /agent/<id>` with the `X-Where-*` headers (terminal, Rex/Herdr/iTerm/tmux pane, tty, the
app around it, the agent's pid), so the click and the reply find the session. It never blocks the session (1 s
timeout, always exit 0) and prints nothing; if the agent reads the hook's stdout, wrap it and print what it expects
(Gemini's hook prints `{}`, Antigravity's Stop prints `{"decision":"stop"}`). With `FISHBOTS_HOOK_LOG=1`, the last
event is kept in `~/Library/Logs/Fishbots/agent-<id>-last.json`, to study the agent's format.

If its JSON isn't in Claude Code's shape, translate it before posting: in a small script, in the agent's plugin
(opencode's does it in JavaScript and sends the `X-Where-*` headers itself), or, when only names differ, with the
manifest's maps. Never hook a step where the agent waits for the hook's decision (a "before tool" hook that must
allow or deny): a slow or failed hook there blocks the agent.

### 3. The manifest (optional)

Without one, `<id>` is also the agent's process name and the fish follows the terminal. With one,
`~/Library/Application Support/Fishbots/agents/<id>.json` (`fishbots agent new <id>` writes a starting one):

```json
{
  "id": "aider",
  "name": "Aider",
  "processNames": ["aider"],
  "fish": "slender",
  "timbre": "pluck",
  "events": {"turn_start": "UserPromptSubmit", "turn_end": "Stop"},
  "tools": {"run_command": "Bash", "edit_file": "Edit"}
}
```

- `id`: lowercase letters, digits and `-`; the route and the fish's source. The built-in agents' ids are taken.
- `processNames`: words in the agent's process path (lowercase match), checked before typing into its terminal.
- `fish`: a fish kind (`oval`, `slender`, `puffer`, `angelfish`, `stingray`, `octopus`, `lanternfish`… or one from a
  pack); without it, the kind follows where the session runs (terminal, editor, Rex).
- `timbre`: `pluck`, `bell`, `pad`, `bass`, `glass`, `bubble`, `soft`, `rhodes`, `flute` or `kalimba`.
- `events`, `tools`: the agent's names → Claude Code's. Names not listed pass as they are.
- `launch` (optional): the command that starts a session, as an array, with `{prompt}` where the first prompt goes
  and `{model}` where the model asked for goes (`["aider", "--model={model}", "--message", "{prompt}"]`; an argument
  whose value wasn't given is left out). With it, `fishbots spawn --agent <id>` can start the agent in a new pane
  ([extensions.md](extensions.md), point 11).

Whoever uses the aquarium can still pick another fish for the whole agent (Preferences → General → Agents → Each
agent's fish) or for one project (the fish menu); those win over the manifest's `fish`.

Manifests are read when the app opens. After adding or changing one, reload: **Preferences → General → Agents →
Reload**, `fishbots agent reload`, or `POST /agents/reload`. Fish already in the aquarium take the new look; an agent
whose manifest was removed goes back to the defaults (its fish keep working). Problems (invalid JSON, a taken id)
show in that same section and in `fishbots agent list` (`GET /agents`), which also lists every agent the aquarium
understands: the built-in ones and those at `/agent/<id>` (with a manifest, or without one once they sent an event).

Manifests aren't part of packs: packs are the aquarium's look; an agent's manifest travels with its hook.

### 4. Try it

With the app open:

```sh
fishbots agent new aider "Aider"       # the manifest
fishbots agent test aider              # a fake session: prompt, Read/Edit/Bash, a reply ending in a question
fishbots agent send aider '{"hook_event_name":"Stop","session_id":"s1","cwd":"/tmp","last_assistant_message":"ok"}'
fishbots agent list                    # every agent (built in, /agent/<id>) and manifest problems
```

Then run the real agent once and check the fish: busy on the prompt, the tools animating, done with the reply.

### What still needs Swift

Reading the agent's own conversation files (context size, branch, title from the log), renaming conversations from
the aquarium, and answering permission requests from the card. Those live in a built-in provider
(`Sources/Fishbots/Providers.swift`; see `docs/extensions.md`).
