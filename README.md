# Spicetify Plus

Spicetify Plus is a Windows menu wrapper for the official Spicetify CLI, Marketplace, themes, extensions, and custom apps. It does not fork Spicetify internals; it drives the upstream tools and keeps source metadata in `spicetify-plus.catalog.json`.

Current project version: `2.0.0`

Language: [English](README.md) | [Persian](README-FA.md)

## What It Manages

- Spotify install, update, and explicit confirmed removal.
- Spicetify CLI install/update from the real latest Windows release asset.
- Spicetify Marketplace install from the official Marketplace release.
- Official extensions from `spicetify/cli/Extensions`.
- Built-in custom apps from `spicetify/cli/CustomApps`: `lyrics-plus`, `new-releases`, and `reddit`.
- Official themes from `spicetify/spicetify-themes`, only when both `color.ini` and `user.css` exist.
- Community apps defined in `spicetify-plus.catalog.json`.

`betterLibrary` is kept in the catalog as `Deprecated` because its upstream repository is archived.

## Files

- `spicetify-plus.ps1` - main PowerShell script.
- `spicetify-plus.exe` - executable built from the script.
- `spicetify-plus.catalog.json` - official and community source catalog.
- `tools/refresh-upstream.ps1` - clones/updates local reference repositories.
- `tools/build-exe.ps1` - builds `spicetify-plus.exe` with `ps2exe`.
- `.upstream/` - local upstream clones, ignored by git.
- `.tools/` - local build tools, ignored by git.

The preset JSON files in the repository are not used by the updater and are outside the maintenance scope.

## Requirements

- Windows 10 or 11.
- Windows PowerShell 5.1 or newer.
- Internet access for GitHub, Spotify, and upstream downloads.
- Git, only if you want to refresh `.upstream/`.

## Usage

Run the script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\spicetify-plus.ps1
```

Run the executable:

```powershell
.\spicetify-plus.exe
```

Run a read-only smoke test:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\spicetify-plus.ps1 -SelfTest -NoPause
```

Use a custom upstream reference path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\spicetify-plus.ps1 -SelfTest -NoPause -UpstreamRoot .upstream
```

## Menus

Main menu:

1. Install Spotify
2. Update Spotify
3. Remove Spotify
4. Install Spicetify
5. Install Spicetify Marketplace
6. Update Spicetify
7. Spicetify Settings
8. Remove Spicetify
9. GitHub API Token Settings
10. Run Self Test

Settings menu includes backup/apply, auto, restore, refresh, developer tools, extension/app/theme management, config settings, read-only launch flag inspection, path information, self-test, upstream refresh, backup clearing, Spotify update blocking, advanced refresh/watch, theme color management, and config directory opening.

## Refresh Upstream References

Clone or update reference repositories:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\refresh-upstream.ps1
```

Large mirror/archive repositories are skipped by default to avoid long clone times:

- `spicetify/winget-pkgs`
- `spicetify/xpui-archive`
- `spicetify/pkgs`
- `spicetify/classmaps`

Include them explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\refresh-upstream.ps1 -IncludeLargeMirrors
```

## Build

Build the executable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-exe.ps1
```

The build script uses an existing `Invoke-PS2EXE` command when available, otherwise it downloads `ps2exe` into `.tools/`.

## Safety Notes

- `-SelfTest` is read-only. It validates catalog sources and release resolvers without installing, applying, backing up, restoring, or changing Spotify/Spicetify config.
- Spicetify configuration changes go through `spicetify config`.
- Spotify removal and cleanup require explicit confirmation.
- GitHub API token storage keeps the previous local token path for compatibility.

## Validated Snapshot

As of the latest maintenance pass on 2026-07-01:

- `spicetify/cli` latest release resolved as `v2.43.2`.
- Marketplace latest release resolved as `v1.0.8`.
- Official extension discovery reads from upstream CLI.
- Local official themes are validated by checking `color.ini` and `user.css`.

Run `-SelfTest` to refresh this information on your machine.
