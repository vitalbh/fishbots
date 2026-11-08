#!/bin/sh
# Uptime plugin for Fishbots (runs every minute): turns a StatusCake SwiftBar/xbar plugin's output into the tank.
#  - a flag "uptime" with ▲ up ▼ down: green when everything is up, amber when something is down, red when a
#    "Critical" test is down
#  - each test that is down is a bottle on the sand with the reason; clicking opens the test
#  - a shark patrols while a Critical test is down
#  - a test that goes down sets off a lightning; one that comes back, fireworks
# It doesn't talk to StatusCake itself (no API key here): it runs the plugin you already have, which prints
#   ▲ 9 ▼ 2 | color=…
#   OFF: Site / Region / Critical / HTTP 503: … | href='https://app.statuscake.com/AllStatus.php?tid=…'
# Which plugin: FISHBOTS_UPTIME_CMD, set in ~/Library/Application Support/Fishbots/plugins.env, e.g.
#   FISHBOTS_UPTIME_CMD="$HOME/plugins-bar/statuscake.10s.cgo"
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
ENV="$HOME/Library/Application Support/Fishbots/plugins.env"
[ -f "$ENV" ] && . "$ENV"
CMD="$FISHBOTS_UPTIME_CMD"
[ -n "$CMD" ] || { echo "set FISHBOTS_UPTIME_CMD in plugins.env" >&2; exit 1; }
[ -x "$CMD" ] || { echo "uptime plugin not found: $CMD" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

STATE="$HOME/Library/Caches/Fishbots/uptime"
mkdir -p "$STATE"
# the first run only learns who is down (no lightning for what was already down)
first=false
[ -f "$STATE/down.json" ] || { echo '[]' > "$STATE/down.json"; first=true; }

out=$(cd /tmp && perl -e 'alarm 40; exec @ARGV' "$CMD" 2>/dev/null) || { echo "the uptime plugin failed" >&2; exit 1; }
head=$(printf '%s\n' "$out" | head -1)
case "$head" in *▲*) ;; *) echo "unexpected output: $head" >&2; exit 1 ;; esac

# only the "OFF:" lines of the first section (the next ones are history)
printf '%s\n' "$out" | awk 'NR > 1 && /^---/ { n++ } n <= 1 && /^OFF: / { print }' > "$STATE/off.txt"

printf '%s\n' "$head" | jq -R -c --rawfile off "$STATE/off.txt" --slurpfile before "$STATE/down.json" --argjson first "$first" '
  (capture("▲ *(?<up>[0-9]+) *▼ *(?<down>[0-9]+)") // {up: "?", down: "0"}) as $n
  | [$off | split("\n")[] | select(length > 0)
     | capture("^OFF: (?<name>[^|]*?) / (?<why>[^/|]*?) *\\| *href=.(?<link>[^ '\''\"]+)")
     | . + {id: (.link | capture("tid=(?<t>[0-9]+)").t // .name),
            why: (.why | sub(":.*$"; "") | .[0:40]),           # the short reason (the rest is behind the link)
            label: (.name | gsub(" / "; " · ") | sub("Brasil"; "BR") | .[0:30]),
            critical: (.name | test("critical"; "i"))}] as $down
  | ($before[0] // []) as $was            # [{id, label}] from the last run
  | ($down | map(.id)) as $ids
  # the flag
  | {source: "uptime", presence: "summary", kind: "flag", label: "uptime",
     state: (if ($down | any(.critical)) then "error" elif ($down | length) > 0 then "alert" else "ok" end),
     detail: "▲ \($n.up) ▼ \($n.down)", link: "https://app.statuscake.com/YourStatus.php"},
    # one bottle per test down
    ($down[] | {source: "uptime", presence: ("test:" + .id), kind: "bottle", label, detail: .why, link,
                state: (if .critical then "error" else "alert" end)}),
    # the shark: the first critical test down
    ([$down[] | select(.critical)] | first // empty
      | {source: "uptime", presence: "shark", kind: "shark", state: "error", label, detail: .why, link}),
    # transitions since the last run
    (if $first then empty else
      ($down[] | select(.id as $i | $was | map(.id) | index($i) | not) | {source: "uptime", effect: "lightning", label: "\(.label) caiu"}),
      ($was[] | select(.id as $i | $ids | index($i) | not) | {source: "uptime", effect: "fireworks", label: "\(.label) voltou"})
     end)
'

# remembers who is down (id and label) for the next run
jq -n -c --rawfile off "$STATE/off.txt" '
  [$off | split("\n")[] | select(length > 0)
   | capture("^OFF: (?<name>[^|]*?) / [^/|]*?\\|.*tid=(?<id>[0-9]+)")
   | {id, label: (.name | gsub(" / "; " · ") | sub("Brasil"; "BR") | .[0:30])}]' > "$STATE/down.json.tmp" \
  && mv "$STATE/down.json.tmp" "$STATE/down.json"
exit 0
