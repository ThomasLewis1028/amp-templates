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
