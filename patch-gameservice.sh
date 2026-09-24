#!/usr/bin/env bash
# patch-gameservice.sh -- stop R6GameService.dll retrying Ubisoft's dead backend.
#
# Usage: patch-gameservice.sh <system-dir>
#
# UR6GSServers::ProcessInternetSrv registers the server against
# gsconnect.ubisoft.com, which still resolves but answers HTTP 500 - Ubisoft
# decommissioned the backend. The retry never succeeds, so the server logs
# "try again time <seconds>" every 16 seconds forever and blocks while it waits.
#
# The fix is one byte: the conditional jump that guards the registration branch
# becomes unconditional, so the branch falls through.
#
#   offset 0x13b0c (80652)   0x75 (JNZ)  ->  0xEB (JMP)
#
# This is the same single-byte delta as the community pre-patched DLL, applied
# to the depot file in place rather than downloading someone's binary.
#
# Refuses to touch anything it does not recognise: both the stock and the
# patched SHA-256 are pinned, so a Steam depot update makes this a no-op with a
# loud message rather than a blind write to a different binary.
#
# Idempotent - a second run detects the patched hash and exits 0.
set -euo pipefail

STOCK_SHA=3a2f6384315c831ad7f10e499e32da3e0c4674050207ee881162f4542b3eb88f
PATCHED_SHA=4ade5a9684ba76b437a6d5fc7e2fd92a7f720bdfd914d67068ba60e828058889
OFFSET=80652          # 0x13b0c
FROM_BYTE=75          # JNZ
TO_BYTE='\xeb'        # JMP

sysdir="${1:?usage: patch-gameservice.sh <system-dir>}"
dll="$sysdir/R6GameService.dll"

if [[ ! -f "$dll" ]]; then
    echo "patch-gameservice: $dll not found" >&2
    exit 1
fi

current="$(sha256sum "$dll" | cut -d' ' -f1)"

if [[ "$current" == "$PATCHED_SHA" ]]; then
    echo "patch-gameservice: already patched, nothing to do"
    exit 0
fi

if [[ "$current" != "$STOCK_SHA" ]]; then
    echo "patch-gameservice: unrecognised R6GameService.dll (sha256 $current)." >&2
    echo "patch-gameservice: expected the stock depot file. Refusing to patch." >&2
    echo "patch-gameservice: the 'try again time' loop will remain. See docs/decision-log.md DEC-007." >&2
    exit 0
fi

observed="$(dd if="$dll" bs=1 skip="$OFFSET" count=1 status=none | od -An -tx1 | tr -d ' \n')"
if [[ "$observed" != "$FROM_BYTE" ]]; then
    echo "patch-gameservice: byte at offset $OFFSET is 0x$observed, expected 0x$FROM_BYTE. Refusing." >&2
    exit 1
fi

if [[ ! -f "$dll.stock" ]]; then
    cp -p "$dll" "$dll.stock"
fi

printf "$TO_BYTE" | dd of="$dll" bs=1 seek="$OFFSET" count=1 conv=notrunc status=none

result="$(sha256sum "$dll" | cut -d' ' -f1)"
if [[ "$result" != "$PATCHED_SHA" ]]; then
    echo "patch-gameservice: post-patch sha256 $result did not match expected." >&2
    echo "patch-gameservice: restoring stock file." >&2
    cp -p "$dll.stock" "$dll"
    exit 1
fi

echo "patch-gameservice: patched R6GameService.dll (stock copy kept at $(basename "$dll").stock)"
