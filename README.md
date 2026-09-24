# amp-templates

Third-party [AMP](https://cubecoders.com/AMP) Generic-module application
templates, consumed by AMP's ADS as a git-backed configuration repository.

Currently ships one template:

| Template | Application |
|---|---|
| `openrvs.kvp` | Rainbow Six 3: Raven Shield 1.60 dedicated server + OpenRVS, under Wine |

## Repository layout

AMP scans the repository root only — no subdirectories.

```
manifest.json          REQUIRED. Repository descriptor; without it AMP skips
                       the entire repository without logging anything.
openrvs.kvp            Template root (Meta.* / App.* / Console.* / Limits.*)
openrvsconfig.json     Meta.ConfigManifest    - user-facing settings
openrvsmetaconfig.json Meta.MetaConfigManifest - config-file mappings
openrvsports.json      App.Ports        via @IncludeJson[...]
openrvsupdates.json    App.UpdateSources via @IncludeJson[...]
set-ini.sh             Rewrites Key=Value lines in the game's INIs. NOT staged
                       by AMP - fetched into the instance by a FetchURL stage.
install-openrvs.sh     Replaces IpDrv.UdpBeacon with the OpenRVS server actors
                       in [Engine.GameEngine]. Also fetched, not staged.
patch-gameservice.sh   Hash-guarded one-byte patch to R6GameService.dll that
                       stops the dead Ubisoft registration loop. Also fetched.
```

`manifest.json` fields are fixed by AMP (`ADSModule.RepoSpec`, lowercase JSON
property names):

```json
{
  "id": "<guid>",
  "authors": ["..."],
  "origin": "<clone url>",
  "url": "<web url>",
  "imagefile": "",
  "prefix": "",
  "repotype": "AppTemplates"
}
```

`repotype` is `AppTemplates` (`*.kvp` game templates) or `ServiceConfigs`
(`*.json` service specs). A non-empty `prefix` is prepended to every template's
display name as `<prefix> / <name>`.

## Installing on an AMP controller

1. AMP → Configuration → ADS → **Configuration Repositories**, add
   `ThomasLewis1028/amp-templates:main`.
2. Press **Fetch Latest**. AMP clones to
   `~amp/.ampdata/instances/<ADS>/Plugins/ADSModule/DeploymentTemplates/ThomasLewis1028-amp-templates-main/`
   and rebuilds its application cache at the end of the refresh — no restart.
3. The template appears in the Create Instance application list.

Instance creation is not enough on its own — the template's display name
promises OpenRVS, and OpenRVS only lands during the **Update** stages.

## What the update pipeline builds

Steam app `19830` is stock Raven Shield 1.60. OpenRVS is a separate patch, so
`App.UpdateSources` runs, in order:

1. **SteamCMD Download** — app `19830`, forced to the Windows platform.
2. **Fetch set-ini.sh** / **Fetch install-openrvs.sh** /
   **Fetch patch-gameservice.sh** — helper scripts into the instance root.
3. **Install OpenRVS** — release `v1.6` ZIP extracted over `19830/system`.
   Ships `OpenRVS.u`, `openrvs.ini`, `OpenRenderFix.utx`, `R6ClassDefines.ini`
   and `Servers.list`. Must run *after* SteamCMD, since `app_update … validate`
   restores depot files such as `R6ClassDefines.ini`.
4. **Wire OpenRVS server actors** — rewrites `[Engine.GameEngine]` in both
   `system/RavenShield.ini` and `Mods/RavenShield.mod`, replacing
   `ServerActors=IpDrv.UdpBeacon` with `OpenRVS.OpenServer` and
   `OpenRVS.OpenBeacon`.
5. **Patch R6GameService.dll** — kills the Ubisoft registration retry loop.
   Also must run after SteamCMD, for the same reason.
6. **Initialise Wine Prefix** — `wineboot --init --update`.

A correctly patched server logs, on start:

```
Spawning: OpenRVS.OpenServer
Spawning: OpenRVS.OpenBeacon
Resolved api.openrvs.org (184.73.85.28)
[OpenRVS.OpenRVS] info: OpenRVS is up to date (v1.6)
```

`ServerBeaconPort` must be exactly `Port + 1000` and `BeaconPort` exactly
`Port + 2000`, which `openrvsports.json` already encodes as 7777/8777/9777.

### The `try again time` loop

An unpatched server logs `try again time <seconds>` every 16 seconds, forever,
blocking on each retry. That is `UR6GSServers::ProcessInternetSrv` in
`system/R6GameService.dll` retrying registration against
`gsconnect.ubisoft.com`, which still resolves to `203.132.25.34` but answers
HTTP 500 — the Ubi.com backend is gone. Installing OpenRVS does **not** stop
it; the loop is native code, not UnrealScript.

`patch-gameservice.sh` flips one byte — offset `0x13b0c`, `0x75` (`JNZ`) to
`0xEB` (`JMP`) — so the registration branch falls through. It writes only if
the file's SHA-256 matches the stock depot hash *and* the byte at that offset
is `0x75`, verifies the result against the expected patched hash, and keeps the
original as `R6GameService.dll.stock`. A depot update makes it a no-op with a
warning rather than a blind write. See DEC-007.

## Constraints AMP enforces on a template

A `.kvp` that trips any of these is dropped silently:

- `Meta.AppConfigId`, `Meta.DisplayName`, `Meta.Description`,
  `Meta.DisplayImageSource` and `Meta.OS` must all be present.
- `Meta.AppConfigId` must parse as a GUID and be unique across all repositories.
- `Meta.OS` and `Meta.ContainerPolicy` must be valid enum values;
  an empty `Meta.OS` is rejected.
- Presence of a `Meta.Hidden` key hides the template regardless of its value.
- `@IncludeJson[file.json]` filenames must be lowercase (`[a-z\d\-_.]+\.json`)
  and resolve relative to the `.kvp`.
- A template whose `Meta.DisplayName` collides with an already-loaded one is
  renamed to `<name> (<repo dir>)` rather than replacing it.

## Gotchas in update and pre-start stages

`UpdateSource: Executable` passes `UpdateSourceArgs` verbatim to
`Process.Start` as the `Arguments` string. .NET splits that with Windows
rules even on Linux: double quotes group, backslashes escape, and **single
quotes are ordinary characters**. So the outer quoting must be double:

```json
"UpdateSourceArgs": "-c \"WINEPREFIX='{{$FullRootDir}}.wine' /usr/bin/wineboot --init\""
```

Reversing that produces `bash: -c: line 1: unexpected EOF while looking for
matching `''` and the stage fails without stopping the update.

Only `Meta.ConfigManifest` and `Meta.MetaConfigManifest` are copied into a new
instance (as `configmanifest.json` / `metaconfig.json`). Any other file the
template needs — helper scripts, default config files — must be pulled in by a
`FetchURL` stage, exactly as the official templates do.

Path variables resolve with a trailing separator: `{{$FullInstanceDir}}` is the
instance root, `{{$FullRootDir}}` is `App.RootDir`, `{{$FullBaseDir}}` is
`App.BaseDirectory`.

## Testing a change

AMP does not report template parse failures. To check a template before
pushing, compare it against the CubeCoders corpus on the controller:

```bash
ssh ds1.amp
cd ~amp/.ampdata/instances/ADS01/Plugins/ADSModule/DeploymentTemplates
grep -h '^Meta.OS=' CubeCoders-AMPTemplates-main/*.kvp | sort -u
```

See `docs/decision-log.md` for why the repository is laid out this way.
