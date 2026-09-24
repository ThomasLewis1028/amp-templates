#!/usr/bin/env bash
# set-ini.sh -- rewrite existing Key=Value lines in an Unreal Engine 2 style INI.
#
# Usage: set-ini.sh <ini-file> Key=Value [Key=Value ...]
#
# Behavior:
#   - Only rewrites keys that ALREADY exist in the file. It never appends,
#     so a typo'd or nonexistent key is a warning on stderr, not file damage.
#   - Matching is on the start of the line ("Key="), section-agnostic.
#   - Preserves CRLF line endings (Raven Shield's INIs are Windows files;
#     stripping the \r can confuse the engine's parser).
#   - Values are passed to awk through the environment (ENVIRON) instead of
#     awk -v, because -v interprets backslash escapes and would mangle
#     passwords containing "\".
set -euo pipefail

file="${1:?usage: set-ini.sh <ini-file> Key=Value ...}"
shift

if [[ ! -f "$file" ]]; then
    echo "set-ini: $file not found (check the system/ path inside 19830/)" >&2
    exit 1
fi

for pair in "$@"; do
    key="${pair%%=*}"   # everything before the first '='
    val="${pair#*=}"    # everything after the first '='

    KEY="$key" VAL="$val" awk '
        BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VAL"]; hits = 0 }
        {
            line = $0
            cr = ""
            # strip a trailing \r for matching, remember it for output
            if (sub(/\r$/, "", line)) cr = "\r"
            if (index(line, k "=") == 1) {
                print k "=" v cr
                hits++
                next
            }
            print $0
        }
        END {
            if (hits == 0) print "set-ini: key \"" k "\" not found in " FILENAME > "/dev/stderr"
        }
    ' "$file" > "$file.tmp"

    mv "$file.tmp" "$file"
done
