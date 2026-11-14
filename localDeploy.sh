#!/usr/bin/env bash
# Copies the addon from this repo into the game: Interface/AddOns/Circlet, next to this
# checkout (Interface/Circlet). The same as localDeploy.ps1, for Git Bash, macOS or Linux.
# Run it after every change, then /reload in game (restart the game if a file was added or
# removed: the game only reads the file list at startup).
#
# It copies what the release zip would hold: everything except what .pkgmeta's "ignore"
# list leaves out (tests, tools, docs...) and the repo's own files (.git, dist). It mirrors
# the folder: changed files are copied and files the repo no longer has are removed. Plain
# bash (find, cmp, cp), so it runs in Git Bash too.
#
#   ./localDeploy.sh               to ../AddOns/Circlet
#   ./localDeploy.sh /some/Circlet  somewhere else
#   DRY_RUN=1 ./localDeploy.sh     show what it would do, change nothing
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
target="${1:-$(dirname "$root")/AddOns/Circlet}"

[ -f "$root/Circlet.toc" ] || { echo "No Circlet.toc in $root: run this from the repo." >&2; exit 1; }
[ -d "$(dirname "$target")" ] || { echo "No AddOns folder at $(dirname "$target")" >&2; exit 1; }

# What .pkgmeta leaves out of a release, plus the repo's own files.
skip=(.git dist __pycache__)
inside=0
while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^ignore: ]]; then inside=1; continue; fi
    if (( inside )) && [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.+[^[:space:]])[[:space:]]*$ ]]; then
        skip+=("${BASH_REMATCH[1]}"); continue
    fi
    if (( inside )) && [[ -n "${line// }" && ! "$line" =~ ^[[:space:]] ]]; then inside=0; fi
done < "$root/.pkgmeta"

is_skipped() { # $1: a path relative to the repo
    local top="${1%%/*}" name
    for name in "${skip[@]}"; do [ "$top" = "$name" ] && return 0; done
    return 1
}

dry="${DRY_RUN:-}"
changed=0
[ -n "$dry" ] || mkdir -p "$target"

# Copy what's new or different.
declare -A wanted
while IFS= read -r -d '' path; do
    rel="${path#"$root"/}"
    is_skipped "$rel" && continue
    wanted["$rel"]=1
    if ! cmp -s "$path" "$target/$rel"; then
        echo "copy   $rel"
        changed=1
        if [ -z "$dry" ]; then mkdir -p "$(dirname "$target/$rel")"; cp -p "$path" "$target/$rel"; fi
    fi
done < <(find "$root" -type f -print0 | sort -z)

# Remove what the repo no longer has.
if [ -d "$target" ]; then
    while IFS= read -r -d '' path; do
        rel="${path#"$target"/}"
        if [ -z "${wanted[$rel]+x}" ]; then
            echo "remove $rel"
            changed=1
            [ -n "$dry" ] || rm -f "$path"
        fi
    done < <(find "$target" -type f -print0 | sort -z)
    [ -n "$dry" ] || find "$target" -mindepth 1 -type d -empty -delete
fi

if [ -n "$dry" ]; then echo "Would deploy $root -> $target"; else echo "Deployed $root -> $target"; fi
if (( changed )); then
    echo "Files changed: /reload in game (restart the game if files were added or removed)."
else
    echo "Already up to date."
fi
