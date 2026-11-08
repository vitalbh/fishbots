#!/bin/sh
# Plugin template. Name: <name>.<interval>.<ext>, with interval 10s, 5m, 1h…
# (with no interval in the name, the plugin keeps running and every line it writes goes in right away).
# Each stdout line is one JSON of the Fishbots protocol (see the README).
# Entities that disappear from one run to the next leave the tank on their own.
echo '{"source":"example","entity":"one","state":"idle","label":"exemplo","detail":"edite plugins/examples/example.30s.sh"}'
