# Decision log

Append-only. Newest entries at the bottom.

## DEC-001 - Keep template files at the repository root

**Date:** 2026-09-24
**Status:** Decided

Template files (`openrvs.kvp`, `openrvs*.json`, `set-ini.sh`) live at the
repository root, not in a per-template subdirectory.

**Why:** `ADSModule.WebMethods.BuildAppsCache` enumerates each configured
repository with `DirectoryInfo.EnumerateFiles("*.kvp")` — a non-recursive call
against the repository root. Templates in subdirectories are never seen. The
official `CubeCoders/AMPTemplates` repository is flat for the same reason, and
disambiguates by filename prefix (`ark-sa*`, `arma3*`).

**Alternatives considered:** One directory per template — rejected, AMP does
not recurse. Flattening only at publish time via CI — rejected, it adds a build
step to a repository that otherwise has none, and the checkout AMP clones must
already be flat.

**Consequences:** Every future template must namespace its companion files by
filename. Collisions are silent: two templates sharing a `*config.json` name
would overwrite each other's settings.

## DEC-002 - Ship `manifest.json` as a tracked repository descriptor

**Date:** 2026-09-24
**Status:** Decided

Added `manifest.json` at the repository root declaring
`"repotype": "AppTemplates"`.

**Why:** `BuildAppsCache` gates every repository on the file existing:

```csharp
string manifestFile = Path.Combine(d.FullName, "manifest.json");
if (!File.Exists(manifestFile)) { continue; }
```

The `continue` fires before any `.kvp` is read, and before the
`log.Debug("Found configuration repository at ...")` call — so a repository
without the file is skipped with no log output at any level. Without it the
OpenRVS template was invisible in AMP's application list despite the repository
cloning and updating cleanly.

**Alternatives considered:** Copy the template into the CubeCoders checkout —
rejected, AMP does `git reset --hard` on every refresh and would discard it.
Register the directory with a `LOCAL` name prefix, which AMP exempts from
deletion — rejected, `LOCAL` directories are skipped by the git updater, giving
up automatic updates, and they still require the repository to be listed in
`ADS.ConfigurationRepositories` to be scanned.

**Consequences:** `id` must stay stable; AMP keys the repository on it.
`prefix` is deliberately empty, so template display names appear unqualified
alongside CubeCoders' — a future name collision gets auto-renamed to
`<name> (ThomasLewis1028-amp-templates-main)`. Set `prefix` if that becomes
confusing.

## DEC-003 - Double-quote the outer shell string in `Executable` stages

**Date:** 2026-09-24
**Status:** Decided

The Wine prefix stage now reads
`-c "WINEPREFIX='{{$FullRootDir}}.wine' ... "` — outer double quotes, inner
single quotes. It was the other way round, and failed with:

```
WINEDEBUG=-all: -c: line 1: unexpected EOF while looking for matching `''
```

**Why:** `UpdateSteps.Executable` hands `UpdateSourceArgs` straight to
`Process.Start` as the `Arguments` string. On Unix .NET splits that string with
*Windows* rules — double quotes group, backslash escapes, and **single quotes
are ordinary characters**. So `-c 'A="x" B=y prog'` splits into `-c`,
`'A=x`, `B=y`, `prog'`; bash gets `'A=x` as its command string, dies on the
unterminated quote, and reports `$0` as the *next* argument. Reproduced exactly
with a five-line `Process.Start` harness before and after the change.

**Alternatives considered:** The built-in `Wine32`/`Wine64` update steps —
rejected, they hardcode `WINEARCH` and build the prefix path from `App.RootDir`
with no way to override, and they assemble the same `-c '...'` shape at
`GenericModule` line 3168. The `Bash` step type, which wraps the args in
`-c "..."` itself — rejected, it removes the ability to pass a literal
double-quoted value, which the `set-ini.sh` stages depend on.

**Consequences:** Every `Executable` stage in this repo must keep double quotes
on the outside. A setting value containing a literal `"` will still break the
`set-ini.sh` stages; there is no escaping mechanism, so those values have to
stay quote-free.

## DEC-004 - Fetch `set-ini.sh` over HTTP rather than expecting AMP to stage it

**Date:** 2026-09-24
**Status:** Decided

Added a `FetchURL` stage pulling `set-ini.sh` from
`raw.githubusercontent.com/.../main/set-ini.sh` into `{{$FullInstanceDir}}`, and
repointed both pre-start stages from `{{$FullRootDir}}set-ini.sh` to
`{{$FullInstanceDir}}set-ini.sh`.

**Why:** AMP copies only the files named by `Meta.ConfigManifest` and
`Meta.MetaConfigManifest` into a new instance — they land as
`configmanifest.json` and `metaconfig.json`. Nothing else in the template
directory is staged, so `set-ini.sh` never existed inside the instance and both
pre-start stages would have failed on the next start. This is why every
official template that ships a helper script (`arma3managemods.sh`,
`ark-semanagemods.sh`) fetches it from CubeCoders' CDN the same way.

**Alternatives considered:** Embed the script body in a `CreateFile` stage —
rejected, it forces a 1.6 KB shell script through a JSON string literal and
makes the diff unreadable. Inline the `awk` into a `Bash` stage — rejected, the
Server.ini pass alone sets 17 keys. Write the INI through
`Meta.MetaConfigManifest` mappings instead of a script — deferred, revisit if
AMP's `kvp` config type learns to preserve CRLF and inline `;` comments, which
Raven Shield's parser needs.

**Consequences:** Instance updates now require outbound HTTPS to
`raw.githubusercontent.com`. The URL is pinned to `main`, so editing
`set-ini.sh` changes behaviour for every instance on its next update — pin a
tag if that becomes a problem.

## DEC-005 - Install OpenRVS from the pinned v1.6 release, wiring actors by script

**Date:** 2026-09-24
**Status:** Decided

Added two update stages: a `FetchURL` that extracts
`OpenRVS-v1.6.zip` over `19830/system`, and an `Executable` stage running
`install-openrvs.sh` to rewrite `[Engine.GameEngine]` in both
`system/RavenShield.ini` and `Mods/RavenShield.mod`.

**Why:** Steam app `19830` is stock Raven Shield 1.60. The template claimed
OpenRVS in its display name, description and `Meta.URL`, but nothing installed
it — a freshly built instance loaded only stock packages and spawned
`IpDrv.UdpBeacon`. Extracting the ZIP alone is not enough either; OpenRVS'
server instructions require `OpenRVS.OpenBeacon` to *replace* `IpDrv.UdpBeacon`,
and `set-ini.sh` cannot do that because it only rewrites existing single-valued
keys, while `ServerActors` is multi-valued.

The stage runs after SteamCMD deliberately: `app_update … validate` restores
depot files, and `R6ClassDefines.ini` is both a depot file and shipped in the
OpenRVS ZIP. Reversing the order silently reverts the mod.

Verified by running a second `UCC.exe` against a port-shifted copy of
`RavenShield.ini` while the AMP instance kept running, which logged
`Spawning: OpenRVS.OpenServer`, `Spawning: OpenRVS.OpenBeacon`,
`Resolved api.openrvs.org (184.73.85.28)` and
`[OpenRVS.OpenRVS] info: OpenRVS is up to date (v1.6)`.

**Alternatives considered:** Pin to the GitHub `releases/latest` redirect —
rejected, an upstream release would silently change every instance on its next
update with no changelog review. Wire `ServerActors=OpenRenderFix.OpenFix` and
`ServerPackages=OpenRenderFix` as the upstream README instructs — rejected,
release v1.6 ships `OpenRenderFix.utx` but no `OpenRenderFix.u`, and the class
is absent from `OpenRVS.u` (confirmed by scanning its name table), so the actor
would fail to resolve at load. Patch only `RavenShield.ini` and not
`Mods/RavenShield.mod` — rejected, the upstream instructions name the `.mod`
file and both carry an `[Engine.GameEngine]` section; patching both is
idempotent and costs nothing.

**Consequences:** Updates now require outbound HTTPS to `github.com`. Moving to
OpenRVS v1.7 is a deliberate edit here, not a silent drift. If upstream ever
ships `OpenRenderFix.u`, revisit the two omitted lines.

## DEC-006 - Do not patch `R6GameService.dll` from the template

**Date:** 2026-09-24
**Status:** Superseded by DEC-007

The `try again time` loop is left in place. The template does not modify
`system/R6GameService.dll`.

**Why:** The loop is `UR6GSServers::ProcessInternetSrv` retrying server
registration against `gsconnect.ubisoft.com`, which resolves to
`203.132.25.34` but returns HTTP 500 — Ubisoft's backend for this game is gone.
OpenRVS does not address it; the retry is native code in the DLL, and OpenRVS
is UnrealScript. Upstream's own README points at two third-party fixes rather
than shipping one.

Silently mutating a game binary during an update stage is a different class of
action from editing config, and the payoff is cosmetic — log noise and,
per upstream, some stutter. That is the owner's call, not the template's.

**Alternatives considered:** Fetch the pre-patched DLL from
`willroberts/raven-shield-2020` — rejected as an unpinned binary from a
personal repository on the update path. Apply the patch ourselves: the diff
against the stock depot file is exactly one byte, `0x13b0c`, `0x75` (`JNZ`) to
`0xEB` (`JMP`) — deferred rather than rejected, because it is auditable and
needs no third-party binary. Revisit if the stutter turns out to matter in
play, guarded by a SHA-256 check of the stock DLL
(`3a2f6384315c831ad7f10e499e32da3e0c4674050207ee881162f4542b3eb88f`) so a
depot change cannot be patched blind.

**Consequences:** Every server log carries a `try again time` line every 16
seconds. Anything parsing the console — `Console.MetricsRegex`, future
ready-detection — must tolerate it.

## DEC-007 - Patch `R6GameService.dll` in place, guarded by pinned hashes

**Date:** 2026-09-24
**Status:** Decided

Supersedes DEC-006. The template now ships `patch-gameservice.sh` and runs it
as an update stage. It flips one byte in `system/R6GameService.dll`:
offset `0x13b0c` (80652), `0x75` (`JNZ`) to `0xEB` (`JMP`), making the Ubisoft
registration branch fall through unconditionally.

**Why:** DEC-006 deferred this as cosmetic and the owner's call. The owner
called it. The loop was measurable, not theoretical: an unpatched server logged
`try again time` five times in 90 seconds and blocked on each retry. With the
patch applied, a 90-second run of the same server on shifted ports logged the
message zero times while still reaching
`[OpenRVS.OpenRVS] info: OpenRVS is up to date (v1.6)`.

The script refuses to write unless the file's SHA-256 is exactly the stock
depot hash, *and* the byte at the offset is `0x75`, *and* the post-write hash
equals the expected patched hash — otherwise it restores the backup and fails.
A Steam depot update therefore turns it into a loud no-op rather than a blind
write into a binary it no longer understands. The stock file is preserved as
`R6GameService.dll.stock`.

**Alternatives considered:** Download the pre-patched DLL from
`willroberts/raven-shield-2020` — still rejected; the delta is one byte we can
apply ourselves, and fetching an unpinned binary from a personal repository on
every update is a worse supply chain than a hash-guarded `dd`. Run ChrisWak's
`R6GameServicePatcher` — rejected, it is a Windows GUI tool and cannot run in
an update stage. Leave it to a manual post-install step — rejected, it would be
lost on every instance rebuild, which is exactly how this was missed the first
time.

**Consequences:** The stage must run after SteamCMD, since
`app_update … validate` restores the depot DLL. `R6GameService.dll.stock` sits
alongside the patched file — do not let a future backup-exclusion rule sweep it
away, it is the only local copy of the original. If OpenRVS or Steam ever ships
a different `R6GameService.dll`, the pinned hashes in the script must be
re-derived before the patch can apply again.
