#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
shopt -s extglob

# For debugging
if [[ "${TRACE-0}" == "1" ]]; then
  set -o xtrace
fi

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDS="$SCRIPTS/../.builds"
TEMP="$SCRIPTS/../.temp"

if ! [ -e "$BUILDS" ]; then
  echo "[!] Checked out builds branch dir missing! Is this running from a workflow?" >&2
  exit 1
fi

# Cleanup
echo "[-] Cleaning up..."
rm -rf "$TEMP"
mkdir "$TEMP" "$TEMP/manifests"

# Read all plugin repository names
mapfile -t repos < "$SCRIPTS/../repositories"

# Handle each plugin repository
for repo in "${repos[@]}"; do
  author_name="$(echo "$repo" | awk -F/ '{ print $1 }')"
  repo_path="$TEMP/$repo"
  updater_path="$repo_path/updater.json"

  echo "[-] Cloning builds of $repo..."
  git clone --depth 1 --branch builds "https://github.com/$repo" "$repo_path" || {
    echo "[!] Failed to clone builds of $repo"
    continue
  }

  echo "[-] Parsing manifests..."

  # Extract all the download urls for published plugins
  download_urls="$(jq --compact-output '
    to_entries
      | map({ key: .key, value: .value.build }
      | .key as $name
      | .value |= gsub("%s"; $name))
      | from_entries
    ' "$updater_path")"

  echo "[+] Publishing plugins: $(echo "$download_urls" | jq -r 'keys | join(" ")')"

  # 1. Get the names of all published plugins
  jq --compact-output --raw-output0 'keys[]' "$updater_path" | \

    # 2. Extract the manifest of each plugin
    xargs -0 -I{} unzip -p "$repo_path/{}.zip" manifest.json | \

    # 3. Combine all manifest infos with the corresponding download url
    # 4. Write repo-specific manifest to disk
    jq --slurp --compact-output \
       --argjson downloadUrls "$download_urls" \
       --arg repo "$repo" \
      'map({
        name: .name,
        description: .description,
        version: .version,
        authors: .authors | map(.name),
        url: $downloadUrls[.name],
        repoUrl: "https://github.com/\($repo)",
        changelog: .changelog,
      })' \
    > "$TEMP/manifests/$author_name.json"

  echo "[+] Parsed all plugin manifests!"
done

# Combine all repo manifests into one
jq --slurp --compact-output 'flatten' "$TEMP"/manifests/*.json > "$BUILDS/manifest.json"
echo "[+] Merged all plugin manifests!"
