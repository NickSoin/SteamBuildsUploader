# Steam Depot Build Uploader

Small Windows tool for uploading one local build folder to a Steam depot through SteamCMD.

Forked from [RPicster/Steam-Upload-GUI](https://github.com/RPicster/Steam-Upload-GUI) and simplified for a direct depot-upload workflow.

## Features

- One action: **Upload new build to depot**.
- Explicit build folder, App ID, and Depot ID.
- Remembers the last three values.
- Shows live SteamCMD output without blocking the UI.
- Reuses the cached SteamCMD login; password login is used only when the cache is missing or expired.
- Excludes local settings, credentials, logs, and compiled builds from Git.

## Required layout

The default local layout is:

```text
SteamTools/
├─ Steam-Upload-GUI/
│  └─ SteamUploadGUI.exe
└─ steamworks_sdk_164/
   └─ sdk/tools/ContentBuilder/
```

The ContentBuilder path remains editable in the application.

## Usage

1. Start `SteamUploadGUI.exe`.
2. Verify the ContentBuilder path reports `SteamCMD ready`.
3. Add or select a Steamworks user.
4. Click **Upload new build to depot**.
5. Enter the build folder, App ID, and Depot ID.
6. Follow Steam Guard instructions if SteamCMD requires confirmation.

SteamPipe creates a new build but does not automatically set it live on a Steam branch.

## Build from source

Requires Godot `3.5.3` with Windows export templates installed.

```powershell
Godot_v3.5.3-stable_win64.exe --no-window --path src --export "Windows Desktop"
```

The executable is generated in `dist/SteamUploadGUI.exe`.

## License

MIT. See [LICENSE](LICENSE).
