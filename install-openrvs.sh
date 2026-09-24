#!/usr/bin/env bash
# install-openrvs.sh -- wire the OpenRVS server actors into Raven Shield's
# engine configuration.
#
# Usage: install-openrvs.sh <system-dir> <ini-file> [<ini-file> ...]
#
# The OpenRVS release ZIP only drops files into system/; the server still
# spawns the stock IpDrv.UdpBeacon until the [Engine.GameEngine] section is
# rewritten. Per the OpenRVS server instructions, OpenRVS.OpenBeacon *replaces*
# IpDrv.UdpBeacon rather than sitting alongside it.
#
# OpenRenderFix is deliberately not wired in: release v1.6 ships
# OpenRenderFix.utx but no OpenRenderFix.u, so ServerActors=OpenRenderFix.OpenFix
# would reference a class that does not exist and fail at load.
#
# Idempotent - running it twice leaves the file unchanged. Preserves CRLF.
set -euo pipefail

sysdir="${1:?usage: install-openrvs.sh <system-dir> <ini-file> ...}"
shift

if [[ ! -f "$sysdir/OpenRVS.u" ]]; then
    echo "install-openrvs: $sysdir/OpenRVS.u missing - did the OpenRVS ZIP extract?" >&2
    exit 1
fi

for file in "$@"; do
    if [[ ! -f "$file" ]]; then
        echo "install-openrvs: $file not found, skipping" >&2
        continue
    fi

    awk '
        BEGIN { section = ""; placed = 0 }

        function emit(text) {
            print text cr
        }

        {
            line = $0
            cr = ""
            if (sub(/\r$/, "", line)) cr = "\r"

            # Section headers
            if (line ~ /^\[.*\]$/) {
                # Leaving GameEngine without having placed the actors? Do it now.
                if (section == "Engine.GameEngine" && !placed) {
                    emit("ServerActors=OpenRVS.OpenServer")
                    emit("ServerActors=OpenRVS.OpenBeacon")
                    placed = 1
                }
                section = substr(line, 2, length(line) - 2)
                print $0
                next
            }

            if (section == "Engine.GameEngine") {
                # Drop the stock beacon and any previous run of this script.
                if (line == "ServerActors=IpDrv.UdpBeacon" ||
                    line == "ServerActors=OpenRVS.OpenServer" ||
                    line == "ServerActors=OpenRVS.OpenBeacon") {
                    next
                }
                # Insert ahead of the ServerPackages block.
                if (!placed && line ~ /^ServerPackages=/) {
                    emit("ServerActors=OpenRVS.OpenServer")
                    emit("ServerActors=OpenRVS.OpenBeacon")
                    placed = 1
                }
            }

            print $0
        }

        END {
            if (section == "Engine.GameEngine" && !placed) {
                emit("ServerActors=OpenRVS.OpenServer")
                emit("ServerActors=OpenRVS.OpenBeacon")
                placed = 1
            }
            if (!placed) {
                print "install-openrvs: no [Engine.GameEngine] section in " FILENAME > "/dev/stderr"
                exit 1
            }
        }
    ' "$file" > "$file.tmp"

    mv "$file.tmp" "$file"
done
