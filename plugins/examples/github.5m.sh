#!/bin/sh
# GitHub plugin for Fishbots (runs every 5 min).
#  - your open PRs become fish: CI ok = ok, running = busy, failed = error
#  - PRs where your review is requested become fish waiting for you
#  - clicking the fish opens the PR
#  - a merged PR (last 30 min) leaves the tank celebrating
# Uses the already authenticated gh. Account: FISHBOTS_GH_USER (default: the active gh account).
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
GH_USER="${FISHBOTS_GH_USER:-$AQUARIO_GH_USER}"
[ -n "$GH_USER" ] && export GH_TOKEN="$(gh auth token -u "$GH_USER" 2>/dev/null)"

gh api graphql -f query='
query {
  viewer {
    pullRequests(first: 6, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes { number title url repository { name nameWithOwner }
              commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }
    }
  }
  merged: search(query: "is:pr author:@me is:merged merged:>='"$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)"'", type: ISSUE, first: 10) {
    nodes { ... on PullRequest { number repository { nameWithOwner } } }
  }
  review: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 6) {
    nodes { ... on PullRequest { number title url repository { name nameWithOwner } } }
  }
}' --jq '
  (.data.viewer.pullRequests.nodes[] | {
      source: "github", entity: ("pr:" + .repository.nameWithOwner + "#" + (.number|tostring)),
      label: (.repository.name + " #" + (.number|tostring)), detail: .title[0:48], link: .url,
      state: ((.commits.nodes[0].commit.statusCheckRollup.state // "NONE") as $s
               | if $s == "SUCCESS" then "ok" elif $s == "FAILURE" or $s == "ERROR" then "error"
                 elif $s == "PENDING" or $s == "EXPECTED" then "busy" else "idle" end) }),
  ((.data.review.nodes // [])[] | select(.number != null) | {
      source: "github", entity: ("review:" + .repository.nameWithOwner + "#" + (.number|tostring)),
      label: ("revisar " + .repository.name + " #" + (.number|tostring)), detail: .title[0:48], link: .url,
      state: "waiting" }),
  ((.data.merged.nodes // [])[] | select(.number != null) | {
      source: "github", entity: ("pr:" + .repository.nameWithOwner + "#" + (.number|tostring)), state: "end", party: true })
'
