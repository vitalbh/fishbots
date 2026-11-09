---
name: fishbots-agents
description: Connect another coding agent (Aider, Amp, Goose, Kiro, a custom CLI…) to the Fishbots aquarium app without changing the app — its hook or plugin posts events to POST /agent/<id>, an optional manifest names it and maps its events and tools, and its sessions become full agent fish. Use when the user wants an agent that Fishbots doesn't support yet to show up in the aquarium, or to fix, reload or test one.
---

# Connecting an agent to Fishbots

Fishbots turns each coding-agent session into a fish. Agents it doesn't know join through `POST /agent/<id>`:
events in Claude Code's hook shape, an optional manifest, no Swift and no rebuild. The full guide is
`docs/agents.md` in the Fishbots repository; this is what you need to do the job.

## Find the tools

The `fishbots` CLI lives in the repository at `bin/fishbots` (try `command -v fishbots` first). The app must be
running for `agent list | reload | test | send` (it listens on 127.0.0.1, port `FISHBOTS_PORT` or 7777). The shared
hook is `plugins/common/hook.sh` in the same repository.

## 1. Learn the agent's hooks first

Read the agent's own docs (or source) for: where hooks are configured, which events exist, what JSON each gets
(stdin? arguments? environment?), whether the hook's stdout is read and what it must print, and its tool names.
If you can run the agent, log real events: `FISHBOTS_HOOK_LOG=1` makes the shared hook keep the last one in
`~/Library/Logs/Fishbots/agent-<id>-last.json`. Never guess a format you can observe.

## 2. Map it to Claude Code's events

| `hook_event_name` | effect | fields |
|---|---|---|
| `SessionStart` | new fish | |
| `UserPromptSubmit` | busy | |
| `PreToolUse` | busy + tool animation | `tool_name`, `tool_input` |
| `PostToolUse` | busy | |
| `Notification` | waiting ("permission"/"approve" in `message`); "waiting for your input" → idle | `message` |
| `Stop` | done; waiting if the reply ends in "?" | `last_assistant_message` |
| `StopFailure` | error | |
| `PreCompact` / `SubagentStop` / `SessionEnd` | compacting / a fry leaves / fish leaves | |

Always: `session_id` (stable per conversation) and `cwd`. Optional: `session_title`. Tool names that animate:
`Bash`, `Edit`, `MultiEdit`, `Write`, `Read`, `Grep`, `Glob`, `LS`, `WebFetch`, `WebSearch`, `Task` (a fry),
`TodoWrite` (`tool_input.todos`), `AskUserQuestion` (waiting), `mcp__<server>__<tool>`.

- **Only names differ** → the manifest's `events` and `tools` maps do it; the hook can forward the JSON as is.
- **Fields differ too** → translate in a small script before posting, or in the agent's plugin (the reference is
  `plugins/opencode/fishbots.js`: it builds the JSON and sends the `X-Where-*` headers itself).
- **No event for something** (no permission event, no reply text) → leave it out and say so; don't fake it.

## 3. Wire the hook

```sh
fishbots agent new <id> "<Name>"     # ~/Library/Application Support/Fishbots/agents/<id>.json, then edit it
```

Manifest fields: `id` (lowercase, digits, `-`; built-in ids like `claude-code`, `codex`, `cursor`, `gemini`,
`antigravity` are taken), `name`, `processNames` (words in its process path; checked before typing into its
terminal), `fish` (a kind id: `oval`, `slender`, `puffer`, `angelfish`, `stingray`, `octopus`, `lanternfish`, or a
pack's; omit to follow the terminal), `timbre` (`pluck`, `bell`, `pad`, `bass`, `glass`, `bubble`, `soft`, `rhodes`,
`flute`, `kalimba`), `events`, `tools`.

The agent's hook command: `<repo>/plugins/common/hook.sh agent/<id> '<glob of its executable>'` (it forwards stdin
with where the session runs, never blocks, prints nothing). If the agent reads stdout, wrap it in a script that
prints what the agent expects after calling the shared hook. Put the wrapper and its config template in
`plugins/<id>/` if you're contributing it to the repository.

**Safety rules:**
- Never hook a step where the agent waits for the hook's decision (a "before tool" hook that must allow/deny): a slow
  or failed hook there blocks the agent, and answering "allow" would bypass the user's permissions.
- Never make the hook fail or print to stdout unless the agent requires it.
- Back up the agent's config before editing it, and merge; don't overwrite other hooks.

## 4. Reload and test

```sh
fishbots agent reload                 # after creating or changing a manifest (or Preferences → General → Agents → Reload)
fishbots agent list                   # every agent (built in and /agent/<id>) and manifest problems
fishbots agent test <id>              # a fake session: prompt, Read/Edit/Bash, a reply ending in "?", then it leaves
fishbots agent send <id> '<json>'     # one event, exactly as the hook would send it
fishbots show                         # the aquarium's state: find the fish with source <id>
```

Then run the real agent once and check, with `fishbots show`: the fish appears on the first prompt, is `busy` while
it works, its tools animate, it ends `done` (or `waiting` after a question) with the reply on the card, and the 2nd
line says where it runs. Report what works and what the agent's hooks can't provide.
