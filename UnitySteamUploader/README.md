# Steam Build Uploader for Unity

A deliberately small Unity Editor package for one workflow:

**Unity build -> SteamCMD -> SteamPipe depot -> optional beta branch**

No Steamworks.NET dependency. No CI system. No password storage.

## Features

- `Tools -> Steam -> Build Uploader`
- Multiple named upload targets, e.g. `Internal`, `Playtest`, `QA`
- One-click **Build & Upload**
- **Upload Existing Build** when you do not need to rebuild
- Uses Unity `BuildPipeline.BuildPlayer`
- Generates SteamPipe app/depot VDF files automatically
- Uploads through official SteamCMD
- Optional `SetLive` for non-default beta branches
- Live SteamCMD output in the Unity window
- Tries to extract and show the resulting Steam Build ID
- Settings saved per Unity project in `ProjectSettings/SteamUploaderSettings.asset`
- Steam password is never stored

## Requirements

- Unity 2022.3 LTS or newer
- Steamworks partner access for the target app/depot
- SteamCMD installed locally
- A Steam builder account with permission to publish builds

## Install from Git

For the current `unity-plugin` branch/folder layout:

```text
https://github.com/NickSoin/SteamBuildsUploader.git?path=/UnitySteamUploader#unity-plugin
```

Add it in Unity via **Window -> Package Manager -> + -> Add package from git URL**.

## First-time setup

1. Open `Tools -> Steam -> Build Uploader`.
2. Set the path to `steamcmd.exe` / `steamcmd.sh`.
3. Enter your Steam builder username.
4. Log into SteamCMD manually once and complete Steam Guard. SteamCMD keeps its own cached authentication. This package never stores your password.
5. Configure at least one target:
   - App ID
   - Depot ID
   - beta branch, or leave blank
   - build target
   - build directory
   - executable name
6. Press **BUILD & UPLOAD**.

## Branch behaviour

If `Branch` is set, the generated AppBuild VDF uses SteamPipe `SetLive` after a successful build. Steam does not allow automatic `SetLive` for the `default` branch, so leave Branch blank for default and publish that build from Steamworks App Admin.

## Generated files

Temporary VDF scripts and SteamPipe build-cache output are written by default to:

```text
Library/SteamUploader/
```

They are local build tooling files and should not be committed.

## Scope

This package intentionally does not try to replace a general build automation framework. Its scope is just:

```text
Unity -> Steam
```

## License

MIT.
