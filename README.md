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
set-ini.sh             Pre-start stage; writes settings into Server.ini
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

## Testing a change

AMP does not report template parse failures. To check a template before
pushing, compare it against the CubeCoders corpus on the controller:

```bash
ssh ds1.amp
cd ~amp/.ampdata/instances/ADS01/Plugins/ADSModule/DeploymentTemplates
grep -h '^Meta.OS=' CubeCoders-AMPTemplates-main/*.kvp | sort -u
```

See `docs/decision-log.md` for why the repository is laid out this way.
