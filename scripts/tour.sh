#!/bin/sh
# Acts out the aquarium mechanics, one at a time, with test fish. Best with the app in fast mode:
#   open --env FISHBOTS_FAST=1 build/Fishbots.app && scripts/tour.sh
cd "$(dirname "$0")/.."
A=bin/fishbots; U="http://127.0.0.1:${FISHBOTS_PORT:-7777}/event"
post() { curl -s -m 2 -H 'Expect:' -X POST "$U" -d "$1" >/dev/null; }
hook() { printf '%s' "$1" | env -u REX_BLOCK -u REX_SESSION plugins/claude-code/hook.sh; }
say() { echo "▸ $1"; }

say "arriving: a project with two fish, a session, a PR"
$A state test sick busy "projeto-x" >/dev/null; $A state test sibling busy "projeto-x" >/dev/null
post '{"source":"github","entity":"pr:tour#1","state":"ok","label":"tour #1"}'
post '{"source":"github","entity":"pr:tour#2","state":"ok","label":"tour #2"}'
hook '{"session_id":"tour-parent","hook_event_name":"UserPromptSubmit","cwd":"/tmp/session-with-subagents"}'
sleep 8

say "tools: Edit nibbles the weed, Bash blows bubbles, Grep forages in the sand, WebSearch peeks at the surface"
for t in Edit Edit Bash Grep Grep WebSearch; do hook '{"session_id":"tour-parent","hook_event_name":"PreToolUse","tool_name":"'$t'","cwd":"/tmp/session-with-subagents"}'; sleep 3; done
sleep 2

say "subagents: 3 fry are born behind the session"
for i in 1 2 3; do hook '{"session_id":"tour-parent","hook_event_name":"PreToolUse","tool_name":"Task","cwd":"/tmp/session-with-subagents"}'; sleep 0.6; done
sleep 6

say "error: projeto-x gets sick (its sibling will look after it); the octopus tour #1 squirts ink"
$A state test sick error >/dev/null
post '{"source":"github","entity":"pr:tour#1","state":"error"}'
sleep 10

say "waiting: comes to the glass (in fast mode, the glass fogs up in ~7 s)"
$A state test wait waiting "esperando você" >/dev/null
sleep 12

say "done: knock-knock and a pearl in the sand (hover it)"
$A state test task busy "tarefa" >/dev/null; sleep 3; $A state test task done >/dev/null
sleep 5

say "healed: projeto-x does a little spin and swims again"
$A state test sick busy >/dev/null
sleep 5

say "subagents finish: the fry leave"
for i in 1 2 3; do hook '{"session_id":"tour-parent","hook_event_name":"SubagentStop","cwd":"/tmp/session-with-subagents"}'; sleep 1; done
sleep 4

say "PR merged: tour #2 leaves through the surface, celebrating"
post '{"source":"github","entity":"pr:tour#2","state":"end","party":true}'
sleep 6

say "sleeping: the session stays still (in fast mode it falls asleep in ~24 s)"
hook '{"session_id":"tour-parent","hook_event_name":"Stop","cwd":"/tmp/session-with-subagents"}'
sleep 30

say "end: the test fish leave"
for e in sick sibling wait task; do $A state test $e end >/dev/null; done
post '{"source":"github","entity":"pr:tour#1","state":"end"}'
hook '{"session_id":"tour-parent","hook_event_name":"SessionEnd","cwd":"/tmp/session-with-subagents"}'
