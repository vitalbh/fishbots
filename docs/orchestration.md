# Orchestration: sessions that run sessions

**Nova sessão…** (⌘N, or a click on the clutch of eggs on the sand) starts a session from the aquarium: its task,
folder, agent and model. Its fish hatches from the eggs. A session that launches
others becomes the leader of a school: another fish for as long as it leads (a nautilus, with a chamber of its shell lit for each session at work; a theme can name
another), its sessions smaller behind it in a V, each tied to it by a thread of light.

A session can also command the others (off until you turn on "Sessions can command other sessions" in Settings →
General), which is what an orchestrating agent needs ([docs/extensions.md](extensions.md), point 11;
`fishbots skill install` teaches your agent the cycle):

```sh
fishbots spawn --cwd ../api "implement X; when done, sum it up"   # a new session in a pane beside this one (Rex, Herdr, iTerm, tmux), as its child
fishbots wait claude-code:1f3a codex:9b2c     # until one stops working: which, how, and its last reply
fishbots reply claude-code:1f3a "use the new table"
fishbots stop claude-code:1f3a
fishbots close claude-code:1f3a               # close the pane of a session this one launched
```

## Where new sessions open

**Where new sessions open:** a session another one starts opens beside it, in its terminal (Rex, Herdr, iTerm or tmux). One you start from the aquarium (the eggs, "Nova sessão…", the assistant) opens where **Preferences → General → Sessions → Open new sessions in** says; Automatic is the first one installed of Rex, Herdr, iTerm and tmux. iTerm is driven by AppleScript, so the first time macOS asks to let Fishbots control iTerm (System Settings → Privacy & Security → Automation).

**Sessions with no terminal:** where none of Rex, Herdr, iTerm or tmux can open a pane, a session started from the aquarium ("Nova sessão…", `fishbots spawn`, the assistant) runs in the background, with the aquarium as its terminal: it's a fish like the others, what you write on its card goes to the agent, Esc interrupts it, what it asks leave for shows on its card, and a click on the fish opens the card (there's nowhere else to go). `fishbots spawn --launcher background` asks for one anywhere. It needs a task to start with, works with Claude Code and Codex (Codex can't ask leave in this mode: it stays in its sandbox), and lives while the app is open.

**Each agent's command line** (Preferências → Geral → Agentes): the binary, extra parameters and variables (`CLAUDE_CONFIG_DIR=~/.claude-work`) the aquarium uses when it starts Claude Code or Codex itself, for a new session in a terminal and for the assistant. A shell alias doesn't reach either, so what the alias did goes there.
