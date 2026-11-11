---
name: fishbots-orchestrator
description: Run other coding-agent sessions through the Fishbots aquarium app — start a session in a new terminal pane with a task, wait until it finishes or asks something, read its reply, answer it or interrupt it. Use when the user asks you to orchestrate, delegate or split work across several agent sessions they can watch (as fish in the aquarium), to "spawn a session", or to follow up on sessions already running.
---

# Orchestrating sessions through Fishbots

Fishbots shows each coding-agent session as a fish. With "Sessions can command other sessions" turned on in its
Settings → General, a session can start others and drive them with the `fishbots` CLI (in the Fishbots repository at
`bin/fishbots`; try `command -v fishbots` first). You are an ordinary session: the sessions you start are your
children, each in its own pane, and the person watches all of it in the aquarium.

Every command prints JSON and exits 1 with `{"error": …}` when the app refuses. If it says session control is
off, tell the person where the switch is; don't work around it.

## The cycle

```sh
# 1. start a child with its whole task as the first prompt (several lines are fine)
fishbots spawn --cwd ../api --label "api: pagination" "Implement cursor pagination in …
When you finish, reply with a summary of what changed and anything left open."
#    → {"fish": "claude-code:2d265f0e-…", "state": "born", "parent": "…", "where": {…}}

# 2. wait for the first of your children to stop (done, waiting for an answer, error, or idle if interrupted)
fishbots wait --timeout 1200 claude-code:2d265f0e claude-code:7c1a90b3
#    → {"fish": "…", "state": "done", "reply": "<its last reply, markdown>"}
#      or {"timeout": true}, or {"fish": "…", "gone": true} if its session ended
#    every one of them instead of the first: one answer per fish, in the order given
fishbots wait --all --timeout 1200 claude-code:2d265f0e claude-code:7c1a90b3

# 3. follow up in the same session, or leave it
fishbots reply claude-code:2d265f0e "Also cover the empty-page case."
fishbots stop claude-code:2d265f0e        # Esc: interrupt what it's doing

# 4. when you have what you need from them, close their panes (only the ones you launched)
fishbots close claude-code:2d265f0e claude-code:7c1a90b3
```

A fish is named `source:entity`; the start of the entity is enough when it's unique (`2d265f0e`).
`fishbots show` lists every fish with its `state`, `parent` and what it takes now (`can`).

## What to know

- **The brief goes in `spawn`.** The child starts with no context but the prompt: say what to do, where, what
  "done" means and what to report back. `reply` types a single line into its terminal (line breaks become spaces),
  so keep follow-ups short.
- The child opens in the terminal host you run in (Rex, Herdr or tmux), in a pane next to yours that doesn't take
  the focus (the next ones stack in that column); `--tab` gives it a tab of its own (Rex, tmux).
- **`--agent`** picks another agent (`codex`…); the default is yours. `--cwd` is the folder it works in (default:
  the current one). Children that edit the same files step on each other: give each its own folder or git worktree.
- **`wait` after `reply` is safe**: it waits for what the session says next, not for the reply it already gave.
  `state: "waiting"` comes with `asked`: answer it with `reply`, or pass it on to the person.
- **Permission requests stay with the person.** A child that needs approval shows up as waiting in the aquarium;
  you can't approve it. Say so instead of retrying.
- **Limits:** at most 6 children at work at a time (the ones that finished do not count), and a child can't start children of its own.
- **A `spawn` that times out** opened the pane but no session reported from it (the agent's Fishbots hook isn't
  installed, or it's asking something first, like trusting the folder). The error carries `where`; tell the person.
- A session interrupted with `stop` ends up `idle` (in Rex and Herdr; elsewhere it may keep saying `busy`, so
  `reply` to it instead of waiting): its `reply` is then from the turn before. `idle` only says it's at its prompt:
  a session that finished a minute ago or more is `idle` too, with its final reply, so it isn't a failure by itself.
- **Tidy up after yourself.** A child's pane stays open until you `close` it: do that once you've read its result
  and won't follow up, unless the person wants to look at it (then say which ones you left). At most 6 children
  work at the same time; the ones that finished don't count. Never close what you didn't open.
