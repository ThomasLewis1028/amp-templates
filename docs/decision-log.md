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
