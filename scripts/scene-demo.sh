#!/bin/sh
# Acts out the scene layer (docs/scene.md): each presence's voice and states, then every effect. Listen with the sound on.
#   scripts/scene-demo.sh            everything
#   scripts/scene-demo.sh effects    only the effects
cd "$(dirname "$0")/.."
U="http://127.0.0.1:${FISHBOTS_PORT:-7777}/event"
post() { curl -s -m 2 -H 'Expect:' -H 'Content-Type: application/json' -X POST "$U" -d "$1" >/dev/null; }
say() { echo "▸ $1"; }
nap() { perl -e "select(undef,undef,undef,$1)"; }

if [ "$1" != "effects" ]; then
  for k in shark submarine turtle jellyfish seahorse crab starfish bottle hourglass anchor flag chest battery; do
    say "$k: arrives, waits for you, alert, error, done"
    post "{\"source\":\"demo-scene\",\"presence\":\"$k\",\"kind\":\"$k\",\"state\":\"ok\",\"label\":\"$k\",\"value\":0.4}"; nap 2
    for s in waiting alert error done; do
      post "{\"source\":\"demo-scene\",\"presence\":\"$k\",\"state\":\"$s\",\"detail\":\"$s\"}"; nap 1.6
    done
    post "{\"source\":\"demo-scene\",\"presence\":\"$k\",\"state\":\"end\"}"; nap 0.8
  done
  say "the plugin picks another voice: a shark that sounds like a bell"
  post '{"source":"demo-scene","presence":"bellshark","kind":"shark","state":"waiting","label":"sino","sound":"bell"}'; nap 2.5
  say "…and a silent one"
  post '{"source":"demo-scene","presence":"bellshark","state":"error","sound":"none","detail":"silencioso"}'; nap 2
  post '{"source":"demo-scene","presence":"bellshark","state":"end"}'
fi

if [ "$1" != "effects" ]; then
  say "weather: rain and waves, then warm water, then cold water with fog (scene controls, docs/scene.md)"
  post '[{"source":"demo-scene","gauge":"rain","value":0.9},{"source":"demo-scene","gauge":"waves","value":0.8}]'; nap 6
  post '[{"source":"demo-scene","gauge":"rain","value":0},{"source":"demo-scene","gauge":"waves","value":0.2},{"source":"demo-scene","gauge":"temperature","value":0.95}]'; nap 5
  post '[{"source":"demo-scene","gauge":"temperature","value":0.05},{"source":"demo-scene","gauge":"fog","value":0.8}]'; nap 5
  post '[{"source":"demo-scene","gauge":"rain","value":null},{"source":"demo-scene","gauge":"waves","value":null},{"source":"demo-scene","gauge":"temperature","value":null},{"source":"demo-scene","gauge":"fog","value":null}]'
fi

for e in food fireworks whale splash ink bubbles sparkle ring scare pearl lightning quake school shooting-star; do
  say "effect: $e"
  post "{\"source\":\"demo-scene\",\"effect\":\"$e\",\"label\":\"$e\"}"; nap 3
done
