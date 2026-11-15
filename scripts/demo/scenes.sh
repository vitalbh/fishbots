#!/bin/bash
# Acts out and records the demo video's scenes, one clip each (picture + the app's own sound), in an isolated
# instance (its own home, port and made-up sessions): nothing of yours shows up.
#   scripts/demo/scenes.sh <out dir> [scene…]      scenes: orchestra (the README's) intro tools fry permission sick play themes hours visuals presences visitors widget packs
# Needs Screen Recording permission for the terminal (the recorder). The clips are <out>/<scene>.mp4.
set -e
cd "$(dirname "$0")/../.."
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"; shift
SCENES="${*:-intro tools fry permission sick play themes hours visuals presences visitors widget packs}"
PORT=7798; U="http://127.0.0.1:$PORT"
HOME_DIR="$OUT/home"; T="$HOME_DIR/.claude/projects/demo"
mkdir -p "$T" "$HOME_DIR/Library/Application Support/Fishbots/packs"
for p in packs/examples/*/; do ln -sfn "$PWD/$p" "$HOME_DIR/Library/Application Support/Fishbots/packs/$(basename "$p")"; done

[ -x .build/release/Fishbots ] || swift build -c release
[ .build/demo-record -nt scripts/demo/record.swift ] || swiftc -O scripts/demo/record.swift -o .build/demo-record

nap() { perl -e "select(undef,undef,undef,$1)"; }
do_() { curl -s -m 2 -X POST "$U/test/do?$1" >/dev/null; }
ev() { curl -s -m 2 -H 'Content-Type: application/json' -X POST "$U/event" -d "$1" >/dev/null; }
# hook <session> <project> <event> [extra json fields]
hook() {
  curl -s -m 2 -H 'Content-Type: application/json' -X POST "$U/claude-code" \
    -d "{\"session_id\":\"$1\",\"cwd\":\"/Users/demo/$2\",\"hook_event_name\":\"$3\",\"transcript_path\":\"$T/$1.jsonl\"${4:+,$4}}" >/dev/null
}
# a session's transcript: its title and how much context it uses
transcript() {
  printf '{"type":"ai-title","aiTitle":"%s"}\n{"type":"assistant","gitBranch":"main","message":{"usage":{"input_tokens":%s,"output_tokens":800}}}\n' "$2" "$3" > "$T/$1.jsonl"
}
tool() { hook "$1" "$2" PreToolUse "\"tool_name\":\"$3\""; }
# hookp <session> <project> <event> <leader session>: a session another one launched (its fish swims in the leader's school)
hookp() {
  curl -s -m 2 -H 'Content-Type: application/json' -H "X-Where-Parent: claude-code:$4" -X POST "$U/claude-code" \
    -d "{\"session_id\":\"$1\",\"cwd\":\"/Users/demo/$2\",\"hook_event_name\":\"$3\",\"transcript_path\":\"$T/$1.jsonl\"}" >/dev/null
}
endall() { for s in "$@"; do hook "$s" x SessionEnd; done; }

stop_app() { for p in $(pgrep -x Fishbots); do ps -o command= -p "$p" | grep -q "^.build/release/Fishbots" && kill "$p"; done; nap 1; }
start_app() {
  stop_app
  # the preferences are passed here, so whatever the test domain has saved doesn't matter
  CFFIXED_USER_HOME="$HOME_DIR" FISHBOTS_PORT=$PORT FISHBOTS_CATALOG="file://$PWD/community/index.json" nohup .build/release/Fishbots -language en -readQuestions YES \
    -nowPlaying NO -listenToMusic NO -ambientMusic YES -volume 1 -focus NO -labels minimal -agentFishKinds '{}' \
    -surpriseTheme off -visual auto > "$OUT/app.log" 2>&1 &
  for _ in $(seq 40); do curl -s -m 1 "$U/" >/dev/null && break; nap 0.25; done
  nap 2
  do_ "window=1280,720&footer=off&theme=classic&hour=14"
  PID=$(for p in $(pgrep -x Fishbots); do ps -o command= -p "$p" | grep -q "^.build/release/Fishbots" && echo "$p"; done)
  nap 3
}

# rec <name> <seconds> [display]: records in the background (picture and sound); `finish` waits and joins them
rec() {
  NAME=$1
  do_ "audio=start:$OUT/$NAME.caf"
  .build/demo-record "$PID" "$2" "$OUT/$NAME.mov" $3 >/dev/null &
  REC=$!
  nap 0.3
}
finish() {
  wait $REC
  do_ "audio=stop"
  scripts/demo/mux.sh "$OUT/$NAME.mov" "$OUT/$NAME.caf" "$OUT/$NAME.mp4"
  rm -f "$OUT/$NAME.mov" "$OUT/$NAME.caf" "$OUT/$NAME".*.json
  echo "▸ $OUT/$NAME.mp4"
}

start_app
set +e   # a scene that hiccups shouldn't stop the others

for scene in $SCENES; do case $scene in

orchestra)  # the README's: in the deep sea, a session launches three others and leads them; one asks to run something,
            # it's allowed; a song plays (the betta); a flag of sites and lights of clusters on the glass, one breaks and
            # comes back; they finish one by one, then the leader
  do_ "window=1280,860&hour=13&theme=abyss"
  transcript o0 "Ship checkout v2" 60000
  transcript o1 "Payments API: retries" 30000; transcript o2 "Checkout screens" 25000; transcript o3 "Migration guide" 20000
  ev '{"source":"uptime","presence":"sites","kind":"flag","state":"ok","label":"12 sites up"}'
  for c in prod staging dev; do ev "{\"source\":\"k8s\",\"presence\":\"$c\",\"kind\":\"pilot\",\"state\":\"ok\",\"label\":\"$c\"}"; done
  hook o0 checkout SessionStart; hook o0 checkout UserPromptSubmit
  curl -s -m 2 -X POST "$U/test/now-playing?title=Low%20Tide&artist=The%20Driftwoods" >/dev/null
  nap 5
  rec orchestra 30
  nap 1; tool o0 checkout Read; nap 1.5
  for c in "o1 payments-api" "o2 checkout-web" "o3 docs"; do set -- $c; hookp $1 $2 SessionStart o0; nap 0.4; hookp $1 $2 UserPromptSubmit o0; nap 1.2; done
  nap 1; tool o1 payments-api Edit; tool o3 docs Read; nap 1
  ev '{"source":"k8s","presence":"staging","kind":"pilot","state":"error","label":"staging","detail":"2 pods in CrashLoopBackOff"}'
  nap 1; tool o2 checkout-web Bash; nap 2
  tool o1 payments-api Bash; tool o3 docs Edit; nap 1.5
  curl -s -m 30 -H 'Content-Type: application/json' -H "X-Where-Parent: claude-code:o0" -X POST "$U/claude-code/permission" -d "{\"session_id\":\"o2\",\"cwd\":\"/Users/demo/checkout-web\",\"hook_event_name\":\"PermissionRequest\",\"transcript_path\":\"$T/o2.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm run e2e\",\"description\":\"Run the end-to-end tests\"}}" >/dev/null &
  nap 4; do_ "key=%E2%87%A5"; nap 2.5; do_ "key=a"; nap 1.5
  tool o2 checkout-web Bash; nap 1; hook o3 docs Stop; nap 1
  ev '{"source":"k8s","presence":"staging","kind":"pilot","state":"ok","label":"staging","detail":"healthy again"}'
  ev '{"source":"k8s","effect":"fireworks","label":"staging is back"}'
  nap 1; hook o1 payments-api Stop; nap 1.5; hook o2 checkout-web Stop
  nap 1.5; hook o0 checkout Stop
  finish; endall o1 o2 o3 o0
  for c in prod staging dev; do ev "{\"source\":\"k8s\",\"presence\":\"$c\",\"state\":\"end\"}"; done
  ev '{"source":"uptime","presence":"sites","state":"end"}'; nap 3 ;;

intro)  # night, a few sessions at work, the music
  do_ "hour=22&theme=classic"
  transcript a1 "Payment retries" 60000; transcript a2 "Onboarding screens" 30000; transcript a3 "Release notes" 20000
  hook a1 checkout-api UserPromptSubmit; hook a2 mobile-app UserPromptSubmit; hook a3 docs-site UserPromptSubmit
  nap 6
  rec intro 10
  nap 2; tool a1 checkout-api Bash; nap 3; tool a2 mobile-app Edit; nap 2; tool a3 docs-site Read
  finish; endall a1 a2 a3; nap 3 ;;

tools)  # a session is born; each tool its own gesture
  do_ "hour=14&theme=coral-reef"
  transcript b1 "Rate limiter for the API" 40000
  rec tools 18
  nap 0.5; hook b1 checkout-api SessionStart; nap 2.5; hook b1 checkout-api UserPromptSubmit; nap 1.5
  tool b1 checkout-api Bash; nap 3; tool b1 checkout-api Edit; nap 3; tool b1 checkout-api Grep; nap 3; tool b1 checkout-api WebSearch
  finish; endall b1; nap 3 ;;

fry)  # subagents are fry; context is fat; compacting slims it down
  do_ "hour=15&theme=koi-pond"
  transcript c1 "Migrate to the new SDK" 40000
  hook c1 mobile-app UserPromptSubmit; nap 4
  rec fry 20
  nap 0.5; for _ in 1 2 3; do tool c1 mobile-app Agent; nap 0.6; done
  nap 3; transcript c1 "Migrate to the new SDK" 185000; hook c1 mobile-app PostToolUse; nap 1
  hook c1 mobile-app SubagentStop; hook c1 mobile-app SubagentStop; hook c1 mobile-app SubagentStop
  # (the transcript is read at most every 10 s)
  nap 6; hook c1 mobile-app PostToolUse; nap 1.5; hook c1 mobile-app PreCompact; nap 3.5
  transcript c1 "Migrate to the new SDK" 30000; hook c1 mobile-app SessionStart '"source":"compact"'
  finish; endall c1; nap 3 ;;

permission)  # asks to run something: comes to the glass, reads it aloud; Tab, A allows
  do_ "hour=13&theme=kelp-forest"
  transcript d1 "Deploy the landing page" 50000; transcript d2 "Fix flaky tests" 70000; transcript d3 "Dark mode" 35000
  hook d1 website UserPromptSubmit; hook d2 checkout-api UserPromptSubmit; hook d3 mobile-app UserPromptSubmit; nap 5
  rec permission 22
  nap 1
  curl -s -m 30 -H 'Content-Type: application/json' -X POST "$U/claude-code/permission" -d "{\"session_id\":\"d1\",\"cwd\":\"/Users/demo/website\",\"hook_event_name\":\"PermissionRequest\",\"transcript_path\":\"$T/d1.jsonl\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm run deploy -- --prod\",\"description\":\"Deploy the site to production\"}}" >/dev/null &
  nap 12; do_ "key=%E2%87%A5"; nap 4; do_ "key=a"
  finish; endall d1 d2 d3; nap 3 ;;

sick)  # an error: the fish turns pale and sinks, its project's fish gather; broken CI: the octopus' ink
  do_ "hour=16&theme=lagoon"
  transcript e1 "Search indexing" 60000; transcript e2 "Search UI" 40000; transcript e3 "Search docs" 30000
  hook e1 search UserPromptSubmit; hook e2 search UserPromptSubmit; hook e3 search UserPromptSubmit
  ev '{"source":"github","entity":"pr:search#42","state":"ok","label":"search #42"}'
  nap 6
  rec sick 20
  nap 1; hook e1 search PostToolUseFailure '"tool_name":"Bash","error":"tests failed"'
  nap 5; ev '{"source":"github","entity":"pr:search#42","state":"error","detail":"CI failed"}'
  nap 7; hook e1 search UserPromptSubmit
  finish; endall e1 e2 e3; ev '{"source":"github","entity":"pr:search#42","state":"end"}'; nap 3 ;;

play)  # food, a current, a knock on the glass
  do_ "hour=12&theme=arctic"
  transcript f1 "Billing export" 40000; transcript f2 "Push notifications" 40000
  hook f1 billing UserPromptSubmit; hook f2 mobile-app UserPromptSubmit; nap 5
  rec play 14
  nap 1; do_ "feed=0.35,0.9"; nap 3.5; do_ "drag=0.15,0.5,0.85,0.55"; nap 3.5; do_ "knock=0.6,0.45"; nap 1
  finish; endall f1 f2; nap 3 ;;

themes)  # each theme, a few seconds (with a couple of sessions in it)
  transcript g1 "Payment retries" 50000; transcript g2 "Onboarding screens" 40000
  hook g1 checkout-api UserPromptSubmit; hook g2 mobile-app UserPromptSubmit
  for t in classic coral-reef koi-pond arctic abyss kelp-forest lagoon; do
    do_ "theme=$t&hour=13"; nap 5
    rec "theme-$t" 6; finish
  done
  do_ "theme=classic"; endall g1 g2; nap 3 ;;

hours)  # a day going by: dawn, midday, dusk, night
  do_ "theme=coral-reef&hour=5"; nap 4
  rec hours 12
  for i in $(seq 0 119); do do_ "hour=$(awk "BEGIN{print 5+$i*0.15}")"; nap 0.09; done
  finish; do_ "theme=classic&hour=14"; nap 2 ;;

visuals)  # the visualizers dance to the music (each in a theme of its own)
  for vt in school:classic storm:abyss jellies:coral-reef weeds:kelp-forest; do
    v=${vt%%:*}; do_ "visual=$v&theme=${vt#*:}&hour=22"; nap 4
    rec "visual-$v" 8; finish
  done
  do_ "visual=auto&theme=classic" ;;

presences)  # plugins put things in the water: a shark (an orca, in the arctic) for prod, an hourglass for the build…
  do_ "hour=13&theme=arctic"
  transcript p1 "Payment retries" 50000; hook p1 checkout-api UserPromptSubmit; nap 3
  rec presences 20
  nap 0.5; ev '{"source":"k8s","presence":"prod","kind":"shark","state":"ok","label":"prod"}'
  nap 2; ev '{"source":"ci","presence":"build","kind":"hourglass","state":"busy","label":"build","value":0.3}'
  nap 2; ev '{"source":"mail","presence":"inbox","kind":"bottle","state":"ok","label":"inbox","detail":"4 new"}'
  nap 2; ev '{"source":"release","presence":"v2","kind":"flag","state":"ok","label":"v2.4"}'
  nap 2; ev '{"source":"ci","presence":"build","value":0.8}'
  nap 2; ev '{"source":"k8s","presence":"prod","state":"error","detail":"3 pods in CrashLoop"}'
  nap 4; ev '{"source":"ci","presence":"build","state":"done","value":1}'; ev '{"source":"k8s","presence":"prod","state":"ok","detail":"healthy"}'
  finish
  for x in k8s:prod ci:build mail:inbox release:v2; do ev "{\"source\":\"${x%%:*}\",\"presence\":\"${x#*:}\",\"state\":\"end\"}"; done
  endall p1; nap 3 ;;

visitors)  # the creatures that pass now and then, called on the spot (fishbots summon)
  for th in classic lagoon kelp-forest abyss arctic; do
    do_ "theme=$th&hour=13"; nap 4
    rec "visitor-$th" 16
    nap 0.5; curl -s -m 2 -X POST "$U/event" -d '{"source":"demo","summon":"all"}'; echo " ($th)"
    finish
  done
  do_ "theme=classic" ;;

packs)  # the themes window, then the community catalog: install more, or make your own
  do_ "hour=14"
  rec packs 14 display
  nap 1; curl -s -m 2 -X POST "$U/test/themes" >/dev/null; nap 6
  curl -s -m 2 -X POST "$U/test/catalog" >/dev/null; nap 6
  finish
  osascript -e 'tell application "System Events" to key code 53' 2>/dev/null || true; nap 2 ;;

widget)  # W: a little window in the corner, only who needs you
  do_ "hour=14"
  transcript h1 "Deploy the landing page" 50000; transcript h2 "Release notes" 40000
  hook h1 website UserPromptSubmit; hook h2 docs-site UserPromptSubmit; nap 3
  hook h1 website Stop '"last_assistant_message":"Ready. Should I publish it?"'; nap 4
  rec widget 10 display
  nap 2; do_ "key=w"; nap 6; do_ "key=w"
  finish; endall h1 h2; nap 2 ;;

esac; done

stop_app
