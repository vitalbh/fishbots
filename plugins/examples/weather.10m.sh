#!/bin/sh
# Weather plugin for Fishbots (runs every 10 min), from Open-Meteo (free, no key). It drives the scene controls
# (docs/scene.md): rain → streaks and drops on the surface, wind → waves, temperature → warm or cold water,
# fog → haze. A jellyfish carries the temperature and the sky; a thunderstorm sends lightning.
# Where (environment, or ~/Library/Application Support/Fishbots/plugins.env):
#   FISHBOTS_WEATHER_CITY="Lisboa"                      looked up once (Open-Meteo geocoding) and cached
#   FISHBOTS_WEATHER_LAT=38.72 FISHBOTS_WEATHER_LON=-9.14   or the coordinates
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
ENV="$HOME/Library/Application Support/Fishbots/plugins.env"
[ -f "$ENV" ] && . "$ENV"
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }
CACHE="$HOME/Library/Caches/Fishbots/weather"
mkdir -p "$CACHE"

lat="$FISHBOTS_WEATHER_LAT"; lon="$FISHBOTS_WEATHER_LON"; place="$FISHBOTS_WEATHER_CITY"
if [ -z "$lat" ] || [ -z "$lon" ]; then
  [ -n "$place" ] || { echo "set FISHBOTS_WEATHER_CITY (or _LAT and _LON) in plugins.env" >&2; exit 1; }
  geo="$CACHE/geo.json"
  if [ ! -s "$geo" ] || [ "$(jq -r .query "$geo" 2>/dev/null)" != "$place" ]; then
    q=$(printf '%s' "$place" | jq -sRr @uri)
    curl -s -m 15 "https://geocoding-api.open-meteo.com/v1/search?name=$q&count=1" \
      | jq --arg q "$place" '.results[0] + {query: $q}' > "$geo.tmp" && mv "$geo.tmp" "$geo"
  fi
  lat=$(jq -r '.latitude // empty' "$geo"); lon=$(jq -r '.longitude // empty' "$geo")
  [ -n "$lat" ] || { echo "city not found: $place" >&2; exit 1; }
  place=$(jq -r '.name' "$geo")
fi

now=$(curl -s -m 20 "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,precipitation,wind_speed_10m,cloud_cover,weather_code,is_day&timezone=auto") \
  || { echo "Open-Meteo didn't answer" >&2; exit 1; }
printf '%s' "$now" | jq -e .current >/dev/null 2>&1 || { echo "unexpected answer from Open-Meteo" >&2; exit 1; }

printf '%s' "$now" | jq -c --arg place "${place:-}" '
  .current as $c
  # WMO weather codes, in words
  | ({"0":"céu limpo","1":"quase limpo","2":"parcialmente nublado","3":"nublado","45":"neblina","48":"neblina",
      "51":"garoa fraca","53":"garoa","55":"garoa forte","61":"chuva fraca","63":"chuva","65":"chuva forte",
      "66":"chuva gelada","67":"chuva gelada","71":"neve fraca","73":"neve","75":"neve forte","80":"pancadas fracas",
      "81":"pancadas de chuva","82":"pancadas fortes","95":"tempestade","96":"tempestade com granizo","99":"tempestade com granizo"}
     [$c.weather_code | tostring] // "tempo instável") as $sky
  | ($c.weather_code >= 95) as $storm
  | ([$c.precipitation * 4 / 8, 1] | min) as $rain          # mm in the last 15 min → mm/h; 8 mm/h is heavy rain
  | {source: "weather", gauge: "rain", value: $rain},
    {source: "weather", gauge: "waves", value: ([$c.wind_speed_10m / 45, 1] | min)},
    {source: "weather", gauge: "temperature", value: ([[($c.temperature_2m - 10) / 25, 0] | max, 1] | min)},
    {source: "weather", gauge: "fog", value: (if $c.weather_code == 45 or $c.weather_code == 48 then 0.7 else $c.cloud_cover / 100 * 0.12 end)},
    {source: "weather", presence: "now", kind: "jellyfish",
     state: (if $storm then "alert" else "ok" end),
     label: ("\($c.temperature_2m | round)°" + (if $place != "" then " · \($place)" else "" end)),
     detail: "\($sky) · vento \($c.wind_speed_10m | round) km/h",
     color: (if $c.temperature_2m >= 28 then "#ffb070" elif $c.temperature_2m <= 14 then "#8ec8ff" else "#d8a0ff" end)},
    (if $storm then {source: "weather", effect: "lightning", label: $sky} else empty end)
'
exit 0
