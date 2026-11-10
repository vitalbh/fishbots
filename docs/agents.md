# Connecting another agent

Any coding agent with hooks (or plugins) can live in the aquarium without changing the app: its hook posts events
to `POST /agent/<id>`, and every session becomes a full agent fish. Claude Code, Codex, Cursor, Gemini CLI and
Antigravity are built in; opencode joins this way (`plugins/opencode/fishbots.js`), and it's the reference.

## What the agent gets

- A fish per session, labeled with its folder; the conversation's title on the card.
- Busy while it works, an animation per tool (Bash puffs bubbles, Edit nibbles the seaweed, Read, Grep, WebFetch…),
  fry for subagents (`Task`), pebbles for a todo list (`TodoWrite`), a seahorse for MCP tools (`mcp__server__tool`).
- Waiting when it asks you something, done with its last reply on the card (waiting if the reply ends in a question).
- The 2nd line says where it runs (Rex, Herdr, Ghostty, iTerm, Terminal, tmux, Warp, Cursor…); clicking the fish takes
  you there.
- Reply and Esc from the card, typed into its exact terminal (Rex, Herdr, Ghostty, iTerm, tmux), only after checking
  the agent is the process in front.

## 1. The events

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

## 2. The hook

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

## 3. The manifest (optional)

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
  (`["aider", "--message", "{prompt}"]`). With it, `fishbots spawn --agent <id>` can start the agent in a new pane
  ([extensions.md](extensions.md), point 11).

Whoever uses the aquarium can still pick another fish for the whole agent (Preferences → General → Agents → Each
agent's fish) or for one project (the fish menu); those win over the manifest's `fish`.

Manifests are read when the app opens. After adding or changing one, reload: **Preferences → General → Agents →
Reload**, `fishbots agent reload`, or `POST /agents/reload`. Fish already in the aquarium take the new look; an agent
whose manifest was removed goes back to the defaults (its fish keep working). Problems (invalid JSON, a taken id)
show in that same section and in `fishbots agent list` (`GET /agents`), which also lists every agent the aquarium
understands: the built-in ones and those at `/agent/<id>` (with a manifest, or without one once they sent an event).

Manifests aren't part of packs: packs are the aquarium's look; an agent's manifest travels with its hook.

## 4. Try it

With the app open:

```sh
fishbots agent new aider "Aider"       # the manifest
fishbots agent test aider              # a fake session: prompt, Read/Edit/Bash, a reply ending in a question
fishbots agent send aider '{"hook_event_name":"Stop","session_id":"s1","cwd":"/tmp","last_assistant_message":"ok"}'
fishbots agent list                    # every agent (built in, /agent/<id>) and manifest problems
```

Then run the real agent once and check the fish: busy on the prompt, the tools animating, done with the reply.

## What still needs Swift

Reading the agent's own conversation files (context size, branch, title from the log), renaming conversations from
the aquarium, and answering permission requests from the card. Those live in a built-in provider
(`Sources/Fishbots/Providers.swift`; see `docs/extensions.md`).
