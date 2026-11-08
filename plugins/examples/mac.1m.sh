#!/bin/sh
# Mac plugin for Fishbots (runs every minute): CPU load and battery, as gauges.
ncpu=$(sysctl -n hw.ncpu)
load=$(sysctl -n vm.loadavg | awk '{print $2}')
echo "{\"source\":\"mac\",\"gauge\":\"cpu\",\"value\":$(echo "$load $ncpu" | awk '{v=$1/$2; if (v>1) v=1; printf "%.3f", v}')}"
bat=$(pmset -g batt 2>/dev/null | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
if [ -n "$bat" ]; then
  echo "{\"source\":\"mac\",\"gauge\":\"battery\",\"value\":$(echo "$bat" | awk '{printf "%.2f", $1/100}')}"
  # plugged in (charging or full): the battery at the bottom of the tank glows
  if pmset -g batt | grep -q "AC Power"; then c=1; else c=0; fi
  echo "{\"source\":\"mac\",\"gauge\":\"charging\",\"value\":$c}"
fi
exit 0
