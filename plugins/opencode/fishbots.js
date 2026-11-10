// Fishbots plugin for opencode: each session becomes a fish in the aquarium.
// Install: scripts/install-hooks.sh opencode (links this file into ~/.config/opencode/plugins/).
// It turns opencode's events into Claude Code's hook shape and posts them to Fishbots (POST /agent/opencode), with where
// the session runs (the X-Where-* headers plugins/common/hook.sh sends). Never blocks or fails the session.
// Written from opencode's plugin docs (the function-export plugin API); not yet tried on a real session.

const port = process.env.FISHBOTS_PORT || process.env.AQUARIO_PORT || "7777"
const endpoint = `http://127.0.0.1:${port}/agent/opencode`   // an agent without Swift: see AgentManifests.swift

// where the session runs: opencode runs in the terminal, so it has the terminal's variables
const env = process.env
const where = {
  "X-Where-Term": env.TERM_PROGRAM,
  "X-Where-Rex-Session": env.REX_SESSION,
  "X-Where-Rex-Block": env.REX_BLOCK,
  "X-Where-Herdr": env.HC_TERMINAL_ID,
  "X-Where-Iterm": env.ITERM_SESSION_ID,
  "X-Where-Tmux": env.TMUX_PANE,
  "X-Where-Wezterm": env.WEZTERM_PANE,
  "X-Where-Kitty": env.KITTY_WINDOW_ID,
  "X-Where-Pid": String(process.pid),
  // the session that launched this one (fishbots spawn), if any
  "X-Where-Parent": env.FISHBOTS_PARENT,
}
const headers = { "Content-Type": "application/json" }
for (const [k, v] of Object.entries(where)) if (v) headers[k] = v

// opencode's tools → Claude Code's, so they animate the same way
const tools = {
  bash: "Bash", edit: "Edit", write: "Write", patch: "Edit", multiedit: "MultiEdit", read: "Read", grep: "Grep",
  glob: "Glob", list: "LS", task: "Task", webfetch: "WebFetch", websearch: "WebSearch", todowrite: "TodoWrite",
  question: "AskUserQuestion",
}

function post(body) {
  try {
    fetch(endpoint, { method: "POST", headers, body: JSON.stringify(body), signal: AbortSignal.timeout(1000) })
      .catch(() => {})
  } catch {}
}

export const Fishbots = async ({ directory }) => {
  const folder = {}      // session → its folder
  const title = {}       // session → its title
  const reply = {}       // session → the assistant's last text
  const role = {}        // message → user / assistant
  const prompted = new Set()
  const children = new Set()   // subagent sessions: their parent already shows them as fry

  const send = (session, event, extra = {}) => {
    if (!session || children.has(session)) return
    post({ session_id: session, hook_event_name: event, cwd: folder[session] || directory,
           session_title: title[session], ...extra })
  }

  return {
    event: async ({ event }) => {
      try {
        const p = event.properties || {}
        switch (event.type) {
          case "session.created":
          case "session.updated": {
            const info = p.info || {}
            if (!info.id) return
            if (info.parentID) { children.add(info.id); return }
            if (info.directory) folder[info.id] = info.directory
            const renamed = info.title && title[info.id] !== info.title
            if (info.title) title[info.id] = info.title
            if (event.type === "session.created") send(info.id, "SessionStart")
            else if (renamed) send(info.id, "TitleChanged")   // changes nothing but the title
            break
          }
          case "session.deleted":
            if (p.info?.id) send(p.info.id, "SessionEnd")
            break
          case "message.updated": {
            const info = p.info || {}
            if (!info.id) return
            role[info.id] = info.role
            if (info.role === "user" && !prompted.has(info.id)) {
              prompted.add(info.id)
              send(info.sessionID, "UserPromptSubmit")
            }
            break
          }
          case "message.part.updated": {
            const part = p.part || {}
            if (part.type === "text" && role[part.messageID] === "assistant" && part.text) reply[part.sessionID] = part.text
            break
          }
          case "session.idle":
            send(p.sessionID, "Stop", reply[p.sessionID] ? { last_assistant_message: reply[p.sessionID] } : {})
            delete reply[p.sessionID]
            break
          case "session.error":
            send(p.sessionID, "StopFailure")
            break
          case "permission.updated":
          case "permission.asked":
            send(p.sessionID, "Notification", { message: "permission: " + (p.title || p.permission || "") })
            break
          case "permission.replied":
            send(p.sessionID, "PostToolUse")
            break
        }
      } catch {}
    },
    "tool.execute.before": async (input, output) => {
      try {
        send(input.sessionID, "PreToolUse", { tool_name: tools[input.tool] || input.tool, tool_input: output?.args || {} })
      } catch {}
    },
    "tool.execute.after": async (input) => {
      try {
        send(input.sessionID, "PostToolUse", { tool_name: tools[input.tool] || input.tool })
      } catch {}
    },
  }
}
