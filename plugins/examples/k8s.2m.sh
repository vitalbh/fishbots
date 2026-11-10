#!/bin/sh
# Kubernetes/Flux plugin for Fishbots (runs every 2 min). Read-only: only "kubectl get".
#  - each cluster is a small light on the side glass, in the state's color: green when healthy, breathing blue while Flux reconciles, amber (alert) with
#    pods in CrashLoopBackOff/ImagePullBackOff, red (error) when a Flux Kustomization or HelmRelease fails. It stays quiet while all is well, and grows
#    and says why when something is wrong; a click on any of them lists every cluster
#  - the clusters in FISHBOTS_K8S_HELMS are a ship's wheel fallen on the sand instead (its hub in the state's color, turning while Flux reconciles)
#  - while some cluster is in error, a shark patrols the tank with the failing object and its message
#  - a cluster that recovers sets off fireworks; one that breaks, a lightning
#  - a cluster we can't reach (expired login…) stays as a gray light, nearly out (idle)
# Settings (environment, or ~/Library/Application Support/Fishbots/plugins.env):
#   FISHBOTS_K8S_CONTEXTS="ctx1 ctx2"   which clusters (default: every kubectl context)
#   FISHBOTS_K8S_HELMS="ctx1"            the ones you want to see as a wheel on the sand (default: none, all are lights)
#   FISHBOTS_K8S_TRIM="^my-company-"     a regex cut from the names on the labels
#   FISHBOTS_KUBECTL                     which kubectl (default: the first one on the PATH, rex8s' wrapper included)
ENV="$HOME/Library/Application Support/Fishbots/plugins.env"
[ -f "$ENV" ] && . "$ENV"
PATH="$HOME/.config/rex/rex8s/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
KUBECTL="${FISHBOTS_KUBECTL:-kubectl}"
command -v "$KUBECTL" >/dev/null || { echo "kubectl not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

STATE="$HOME/Library/Caches/Fishbots/k8s"
mkdir -p "$STATE"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fishbots-k8s.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT

if [ -n "$FISHBOTS_K8S_CONTEXTS" ]; then printf '%s\n' $FISHBOTS_K8S_CONTEXTS > "$WORK/contexts"
else "$KUBECTL" config get-contexts -o name > "$WORK/contexts" 2>/dev/null; fi

# one cluster → one JSON summary in $WORK/<n>.json
check() {
  ctx="$1"; out="$2"
  # (big clusters have hundreds of pods: the JSON goes through files, not arguments)
  if ! "$KUBECTL" --context "$ctx" --request-timeout=8s get \
      kustomizations.kustomize.toolkit.fluxcd.io,helmreleases.helm.toolkit.fluxcd.io -A -o json > "$out.flux" 2>"$out.err"; then
    jq -n --arg c "$ctx" --arg e "$(tail -1 "$out.err" | cut -c1-120)" '{ctx: $c, reachable: false, error: $e}' > "$out"
    return
  fi
  "$KUBECTL" --context "$ctx" --request-timeout=8s get pods -A -o json > "$out.pods" 2>/dev/null || echo '{"items":[]}' > "$out.pods"
  jq -n --arg c "$ctx" --slurpfile fs "$out.flux" --slurpfile ps "$out.pods" '$fs[0] as $f | $ps[0] as $p |
    def ready: (.status.conditions // [] | map(select(.type == "Ready"))[0]);
    ($f.items | map({kind, ns: .metadata.namespace, name: .metadata.name, r: ready})) as $objs
    | ($p.items | map((.metadata.namespace + "/" + .metadata.name) as $n
        | [.status.containerStatuses[]?.state.waiting.reason // empty]
        | map(select(. == "CrashLoopBackOff" or . == "ImagePullBackOff" or . == "ErrImagePull"
                     or . == "CreateContainerConfigError" or . == "RunContainerError"))
        | select(length > 0) | {pod: $n, why: .[0]})) as $bad
    | {ctx: $c, reachable: true, pods: ($p.items | length),
       failing: [$objs[] | select(.r.status == "False") | {obj: (.kind + " " + .ns + "/" + .name), msg: (.r.message // "" | .[0:140])}],
       reconciling: [$objs[] | select(.r.status == "Unknown") | .name],
       bad: $bad}' > "$out"
}

[ -f "$STATE/last.json" ] || echo '{}' > "$STATE/last.json"
n=0
while IFS= read -r ctx; do
  [ -n "$ctx" ] || continue
  n=$((n + 1)); check "$ctx" "$WORK/$n.json" &
done < "$WORK/contexts"
wait
[ "$n" -gt 0 ] || exit 0

jq -s -c --slurpfile prev "$STATE/last.json" --arg trim "${FISHBOTS_K8S_TRIM:-^\b\B}" --arg helms "${FISHBOTS_K8S_HELMS:-}" '
  def short: sub($trim; "") | sub("\\s+$"; "") | .[0:22];
  def counts: group_by(.why) | map("\(length) \(.[0].why | sub("BackOff$"; ""))") | join(" · ");
  map(. + {
    state: (if .reachable | not then "idle"
            elif (.failing | length) > 0 then "error"
            elif (.bad | length) > 0 then "alert"
            elif (.reconciling | length) > 0 then "busy"
            else "ok" end)
  }) as $now
  | ($prev[0] // {}) as $before
  | ($helms | split(" ") | map(select(. != ""))) as $wheels
  | ($now[] | {
      source: "k8s", presence: ("cluster:" + .ctx), kind: (if .ctx as $c | $wheels | index($c) then "helm" else "pilot" end), label: (.ctx | short), state,
      detail: (if .reachable | not then "sem acesso: \(.error | .[0:60])"
               elif .state == "error" then "\(.failing[0].obj): \(.failing[0].msg)"
               elif .state == "alert" then (.bad | counts)
               elif .state == "busy" then "Flux reconciliando \(.reconciling | join(", ") | .[0:50])"
               else "\(.pods) pods ok" end)
    }),
    # the shark: the first cluster in error
    ([$now[] | select(.state == "error")] | first // empty
      | {source: "k8s", presence: "shark", kind: "shark", state: "error", label: (.ctx | short),
         detail: "\(.failing[0].obj): \(.failing[0].msg)"}),
    # transitions since the last run: recovered → fireworks, broke → lightning
    ($now[] | select(.reachable) | . as $c | ($before[$c.ctx] // "") as $was
      | if $was == "error" and $c.state != "error" then {source: "k8s", effect: "fireworks", label: "\($c.ctx | short) voltou"}
        elif $was != "" and $was != "error" and $c.state == "error" then {source: "k8s", effect: "lightning", label: "\($c.ctx | short) quebrou"}
        else empty end),
    empty
' "$WORK"/*.json

jq -s 'map({(.ctx): (if .reachable | not then "idle" elif (.failing | length) > 0 then "error"
                     elif (.bad | length) > 0 then "alert" elif (.reconciling | length) > 0 then "busy" else "ok" end)}) | add // {}' \
  "$WORK"/*.json > "$STATE/last.json.tmp" && mv "$STATE/last.json.tmp" "$STATE/last.json"
exit 0
