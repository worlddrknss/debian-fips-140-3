#!/usr/bin/env bash
# Opens, updates or closes "automation" issues from the current state of the
# automated workflows, so a broken pipeline can't go unnoticed:
#   - the latest finished build, security-updates and update-pins run on main
#     (scheduled, dispatched or pushed; pull request builds are excluded);
#   - the open update-pins/auto pull request, when its build failed or it has
#     sat unmerged for more than two days.
# It reads state rather than reacting to events, because GitHub doesn't send
# workflow_run events for runs that GITHUB_TOKEN started (the pin pull
# request and the dispatched builds). Safe to run repeatedly: an issue gets
# one comment per failing run. DRY_RUN=1 prints what it would do.
#
# Requires: gh with GH_REPO set (or run inside the repository), jq.
set -euo pipefail

PIN_BRANCH=update-pins/auto
MAX_PIN_AGE_SECONDS=$((2 * 24 * 3600))

run() {
  if [ -n "${DRY_RUN:-}" ]; then
    printf 'would run:'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

# alert TITLE failing|ok KEY MESSAGE
# KEY is a URL that identifies this failure; an open issue that already
# mentions it gets no further comment.
alert() {
  local title="$1" state="$2" key="$3" message="$4" issue
  issue="$(gh issue list --state open --label automation --limit 100 \
    --json number,title --jq ".[] | select(.title == \"$title\") | .number" | head -n1)"
  if [ "$state" = ok ]; then
    if [ -n "$issue" ]; then
      run gh issue close "$issue" --comment "$message"
    else
      echo "ok: $title"
    fi
    return
  fi
  if [ -z "$issue" ]; then
    run gh label create automation --color B60205 --force
    run gh issue create --title "$title" --label automation \
      --body "$message This issue closes on its own once that's fixed."
  elif gh issue view "$issue" --json body,comments \
      --jq '[.body, .comments[].body] | join("\n")' | grep -qF "$key"; then
    echo "already reported in #$issue: $title"
  else
    run gh issue comment "$issue" --body "$message"
  fi
}

for workflow in build security-updates update-pins; do
  latest="$(gh run list --workflow "$workflow.yml" --branch main --status completed --limit 30 \
    --json event,conclusion,url \
    --jq '[.[] | select(.event != "pull_request")
               | select(.conclusion | IN("success", "failure", "timed_out", "startup_failure"))][0]
          // empty')"
  [ -n "$latest" ] || continue
  conclusion="$(jq -r .conclusion <<<"$latest")"
  url="$(jq -r .url <<<"$latest")"
  if [ "$conclusion" = success ]; then
    alert "Automated $workflow failed" ok "$url" "[$workflow succeeded]($url)."
  else
    alert "Automated $workflow failed" failing "$url" \
      "[$workflow on \`main\`]($url) ended with \`$conclusion\`."
  fi
done

title="Automated pin update blocked"
pr="$(gh pr list --head "$PIN_BRANCH" --state open --limit 1 \
  --json number,url,createdAt,headRefOid --jq '.[0] // empty')"
if [ -z "$pr" ]; then
  alert "$title" ok "" "No pin update is waiting."
  exit 0
fi
pr_url="$(jq -r .url <<<"$pr")"
sha="$(jq -r .headRefOid <<<"$pr")"
created="$(jq -r .createdAt <<<"$pr")"
build="$(gh run list --workflow build.yml --commit "$sha" --limit 10 \
  --json event,status,conclusion,url \
  --jq '[.[] | select(.event == "pull_request")][0] // empty')"
age=$(( $(date -u +%s) - $(jq -rn --arg t "$created" '$t | fromdateiso8601') ))

if [ -n "$build" ] && [ "$(jq -r .status <<<"$build")" = completed ] &&
   [ "$(jq -r .conclusion <<<"$build")" != success ]; then
  build_url="$(jq -r .url <<<"$build")"
  alert "$title" failing "$build_url" \
    "[The build]($build_url) for [the pin update]($pr_url) ended with \`$(jq -r .conclusion <<<"$build")\`, so it won't merge."
elif [ "$age" -gt "$MAX_PIN_AGE_SECONDS" ]; then
  alert "$title" failing "$pr_url" \
    "[The pin update]($pr_url) has been open for more than two days without merging."
else
  alert "$title" ok "$pr_url" "[The pin update]($pr_url) is no longer blocked."
fi
