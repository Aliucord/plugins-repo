#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
shopt -s extglob

# For debugging
if [[ "${TRACE-0}" == "1" ]]; then
  set -o xtrace
fi

if [[ -z "${NEW_REPO_URL:-}" ]]; then
  echo "\$NEW_REPO_URL was not set! No repository to add to the list!" >&2
  exit 1
fi

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORIES="$SCRIPTS/../repositories"

# Parse input url
NEW_REPO=$(perl -ne '
  if (m{^(?:https?://)?(?:www\.)?github\.com/([^/]+?)/([^/]+?)(?:\.git|/|$)}) {
    print "$1/$2\n";
  }
' <<< "$NEW_REPO_URL")
export NEW_REPO

if [[ -z "$NEW_REPO" ]]; then
  echo "Failed to parse input url $NEW_REPO_URL" >&2
  export CLOSE_ISSUE=true
  exit 0
fi

# Add and deduplicate the repo to the list of repos
jq --raw-input --null-input --raw-output \
   --arg newRepo "$NEW_REPO" \
   '[inputs, $newRepo]
    | sort_by(ascii_downcase)
    | unique_by(ascii_downcase)
    | .[]' \
   < "$REPOSITORIES" \
   > "$REPOSITORIES.tmp"

# Replace CRLF with LF
sed 's/\r$//' < "$REPOSITORIES.tmp" > "$REPOSITORIES"
rm "$REPOSITORIES.tmp"
