# Fishbots

**Your coding agents, as an aquarium.** Every Claude Code, Codex or Cursor session on your Mac becomes a fish. You see
at a glance who's working, who finished and who's waiting for you — and you hear it, because the aquarium plays
each session's state as music. Answer them from the fish, from the notch, or from your iPhone.

<!-- GIF (docs/media/fishbots.gif): the tank with 4–5 sessions → one comes to the glass waiting → its card opens → Allow → it swims back to work -->

## What it does

- **Every session is a fish.** It's born when the session starts, swims fast while it works, sinks when idle and
  leaves when the session ends. Subagents are fry, the context window is how fat it is, and each tool has its own
  move (editing nibbles a plant, a shell command puffs bubbles).
- **What needs you comes to the glass.** A session waiting for you queues at the front, and the longer it waits the
  bigger it gets. An error makes it sick: it fades and sinks until it's fixed.
- **You hear it, without looking.** Silence by default; a sound only when something changes. Each session has its own
  short melody, so you know by ear who finished and who's asking.
- **Answer without switching windows.** Hover a fish for its card: the last reply, what it's doing, and
  **Allow / Deny** for a permission request. Type or dictate a reply, or click to jump to its exact terminal pane.
- **In the notch.** Widget mode moves the aquarium into the Mac's notch: who's working on the left, who needs you on
  the right, with the answer buttons right there.
- **On your iPhone and iPad.** The same tank, its cards and the answer buttons, over your network or Tailscale,
  end-to-end encrypted. Sessions keep running on the Mac.
- **An assistant that lives in the tank.** Ask the moray "who's waiting for me?" or "what did the api session do
  today?"; ask it to answer, stop or start a session. It's the agent you already have, running on your account.
- **Sessions that run sessions.** Start a session from the aquarium, or let an agent spawn others and wait for them
  (`fishbots spawn`, `wait`, `reply`): they swim as a school behind their leader.
- **More than agents.** A CI build, a Kubernetes cluster, your PRs, the weather: anything that posts one line of JSON
  becomes a fish or a creature in the tank.
- **Make it yours.** Themes (a reef, the deep sea, a lagoon, a koi pond), packs that add fish, scenery and music
  styles without compiling anything, and a screen saver with your real sessions in it.

## How it works

```
agent hooks ──► POST 127.0.0.1:7777 ──► the tank (Metal) + the synthesizer (AVAudioEngine)
                                     └─► 7778, TLS, opt-in ──► iPhone / iPad
```

Each agent's hooks send its events to the app, on your Mac only. The app turns them into states (`busy`, `waiting`,
`error`, `done`…), each state into how the fish swims and how its melody sounds:

| state | the fish | the sound |
|---|---|---|
| working | swims fast, up high | its melody every few bars |
| waiting for you | comes to the glass, bigger | the start of its melody, a question, and taps on the glass |
| error | sick, sinking | its melody, dissonant until fixed |
| done | comes close, then rests | a knock-knock on the glass |
| idle | sleeps near the sand | quiet |

Nothing leaves the Mac unless you turn on other devices, and then only to devices you paired, encrypted with a key
of their own. The app has no AI model in it: the assistant is your own Claude Code or Codex.

## Getting started

Requires macOS 15 and Swift 6 (Xcode or the command line tools).

```sh
git clone https://github.com/vitalbh/fishbots && cd fishbots
scripts/app.sh && open build/Fishbots.app      # builds build/Fishbots.app
scripts/install-hooks.sh claude-code           # or codex, cursor, antigravity, opencode
```

That's it: start a session and its fish drops into the tank. Press **D** for a demo with fake sessions.

To answer permission requests from the aquarium, add the permission hook too (it can approve tools on your behalf,
so it's never on by default): `scripts/install-hooks.sh claude-code --permission`.

**iPhone:** turn on Preferences → General → Other devices and scan the QR code with the app (`iOS/`,
see [docs/remote.md](docs/remote.md)).

**Uninstall:** `scripts/uninstall.sh` takes the hooks out of every agent, then asks before deleting the app's data.

## Supported agents

| agent | fish | answer permissions | reply from the card |
|---|---|---|---|
| Claude Code | depends on the terminal | ✓ | ✓ |
| Codex | ray | ✓ | ✓ |
| Cursor | angelfish | — | `cursor-agent` only |
| Antigravity, opencode | — | — | — (not tried on real sessions yet) |
| Your own | you choose | — | ✓ |

Any agent with hooks can join without changing the app: [docs/agents.md](docs/agents.md).
Jumping to the session works in Rex, Herdr, iTerm, tmux, Ghostty, Terminal, WezTerm, kitty and VS Code-based editors.

## Documentation

- [Using the aquarium](docs/using.md): every gesture and shortcut, the widget, the cards, the assistant, preferences
- [The sound](docs/sound.md): motifs, ambient music, visualizers
- [Agents and terminals](docs/agents.md): each built-in agent, connecting your own
- [Plugins and protocol](docs/plugins.md): the event JSON, the `fishbots` command, script plugins, webhooks, attention rules
- [Orchestration](docs/orchestration.md): sessions that command other sessions
- [Packs](docs/packs.md) and [the scene](docs/scene.md): themes, fish, creatures, presences
- [iPhone and iPad](docs/remote.md): pairing, security, Tailscale, notifications
- [Extension points](docs/extensions.md) and [development](docs/development.md): the architecture, building, testing, releasing

## License

[MIT](LICENSE)
