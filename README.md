<img src="icon/AppIcon-1024.png" width="128" alt="MultiVolume icon">

# MultiVolume

[![Release](https://img.shields.io/github/v/release/EcossAIah/MultiVolume)](https://github.com/EcossAIah/MultiVolume/releases)
[![License](https://img.shields.io/github/license/EcossAIah/MultiVolume)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)

A menu bar volume control for macOS aggregate and multi-output audio devices.

## Why it exists

macOS can't change the volume of an aggregate or multi-output device. The aggregate has no volume control of its own, so the Sound menu slider is greyed out and the volume keys do nothing.

MultiVolume finds the aggregate's active sub-devices and sets the volume on each one.

It is a from-scratch replacement for [MultiSoundChanger](https://github.com/rlxone/MultiSoundChanger), which has not been updated since 2021. No code was copied from it. The rewrite exists mostly for security reasons:

| | MultiSoundChanger 1.0.1 | MultiVolume |
|---|---|---|
| Accessibility | Requested at launch | Only for the media keys |
| Hardened runtime | Off | On |
| `get-task-allow` entitlement | Present | Absent |
| Architectures | x86_64 only | arm64 + x86_64 |
| Dependencies | CocoaPods | None |
| Private frameworks | `OSD.framework` | None |

The MultiSoundChanger column was checked with `codesign`, `lipo` and `otool` on its 1.0.1 release, and against its source.

The real problem with the original is the combination: an app with the Accessibility permission, plus `get-task-allow`, plus no hardened runtime. Any process running as your user could attach to it or inject a library, then use that permission without macOS asking you again. MultiVolume ships with hardened runtime on and `get-task-allow` off, so that route is closed.

## Install

**Homebrew:**

```sh
brew tap EcossAIah/multivolume https://github.com/EcossAIah/MultiVolume
brew trust ecossaiah/multivolume   # Homebrew asks before using a third-party tap
brew install --cask multivolume
```

Update later with `brew upgrade --cask multivolume`.

**Or by hand:**

1. Download `MultiVolume-<version>.zip` from [Releases](https://github.com/EcossAIah/MultiVolume/releases).
2. Unzip it and drag `MultiVolume.app` to `/Applications`.
3. Open it. A speaker icon appears in the menu bar. The app has no Dock icon.

The release build is signed with a self-signed certificate, not notarized, so Gatekeeper blocks the first launch. On macOS 15 and later, try to open the app once, then go to **System Settings > Privacy & Security** and click **Open Anyway**. The button stays there for about an hour after the blocked launch and asks for an administrator password. If you'd rather not do that, [build from source](#build-from-source). A local build has no quarantine flag, so Gatekeeper doesn't block it.

Because every release is signed with the same certificate, macOS keeps the Accessibility and Input Monitoring grants when you update. (Updating from 1.0.0, which was ad-hoc signed, needs them once more.)

## Usage

Click the menu bar icon to open the panel:

- **Volume slider and mute.** These control the current default output device. On an aggregate device they act on every active sub-device.
- **−10% / −5% / +5% / +10%** buttons for set steps.
- **Output Device** list. Choosing a device makes it the system default, same as the Sound menu. Aggregate devices are tagged `AGG`. Devices without a software volume control get a small slider icon.
- **Refresh** and **Quit** (⌘Q).

Media keys (F10 / F11 / F12) work once the permission is granted (see below):

- Volume up and down change the volume in 1/16 steps. Hold ⇧⌥ for 1/64 steps.
- Mute toggles mute.
- MultiVolume only takes over these keys when the default output is an aggregate device. On any other device it passes them through, so macOS handles them as usual and shows its own volume overlay. For aggregate devices MultiVolume shows its own overlay at the top right of the screen.

To start MultiVolume at login, add it under **System Settings > General > Login Items**.

## Permissions and privacy

Everything except the media keys works with no permissions.

macOS sends the volume keys as system-defined HID events, not normal key presses. The only way to catch them is a `CGEventTap`, and macOS only allows that with the **Accessibility** permission. On some macOS versions, **Input Monitoring** is needed too. The menu shows the state of both, and **Open Settings…** asks for whichever one is missing. Media keys turn on by themselves once access is granted.

How the event tap is limited (`Sources/MultiVolume/MediaKeyMonitor.swift`):

- It listens only for `NX_SYSDEFINED` events. Normal key presses never reach the app, so it can't see what you type.
- It acts only on volume up, volume down and mute. Every other event passes through unchanged.
- Nothing is logged, saved or sent anywhere.

The app has no networking code. It doesn't ask for Screen Recording, Microphone, Camera, Full Disk Access, Contacts or Automation. If it shows up under any of those, something is wrong.

### Verifying a build

```bash
APP=/Applications/MultiVolume.app
codesign -dvvv --entitlements - "$APP" 2>&1 | grep -E "flags=|Signature=|get-task-allow"
lipo -archs "$APP/Contents/MacOS/MultiVolume"
otool -L "$APP/Contents/MacOS/MultiVolume" | grep -i private || echo "no private frameworks"
lsof -i -a -p "$(pgrep -x MultiVolume)"   # prints nothing: no sockets
```

You should see `runtime` in the flags, no `get-task-allow` line, and both architectures.

## Build from source

Requirements:

- macOS 14 or later
- A Swift 6 toolchain: Xcode 16 or later, or the matching Command Line Tools

```bash
git clone https://github.com/EcossAIah/MultiVolume.git
cd MultiVolume
swift test      # unit tests, no audio hardware needed
./build.sh
```

`build.sh` does the following:

- Builds a universal release binary. If the toolchain can't, it falls back to the native architecture.
- Puts together `build/MultiVolume.app` and signs it with hardened runtime.
- Maps the checkout path to `.` and strips debug symbols, so the binary carries no absolute build paths.
- Checks its own output. It fails if hardened runtime is missing, if `get-task-allow` is present, if the app links a private framework, or if the binary contains the checkout path or a home folder path.
- Writes `build/MultiVolume-<version>.zip`.

Options are set with environment variables:

```bash
SIGN_ID="Apple Development: Name (TEAMID)" ./build.sh   # sign with your certificate
BUNDLE_ID=com.example.multivolume ./build.sh            # default: io.github.ecossaiah.multivolume
UNIVERSAL=0 ./build.sh                                  # native architecture only
```

Then install:

```bash
cp -R build/MultiVolume.app /Applications/
```

To keep the Accessibility grant across rebuilds, run `./make-signing-cert.sh` once. It creates a self-signed certificate in your login keychain, and `build.sh` uses it from then on. Any other identity works too via `SIGN_ID` (`security find-identity -v -p codesigning` lists yours).

To publish a release, bump the version in `Resources/Info.plist`, add a `CHANGELOG.md` section for it, commit, and run `./release.sh`. It tests, builds, updates the cask, tags, pushes, and creates the GitHub release.

To regenerate the app icon (needs Python 3 and Pillow):

```bash
python3 icon/generate_icon.py && python3 icon/make_iconset.py
```

## How it works

- `AudioCatalog` lists output devices through the CoreAudio HAL. A device with transport type `kAudioDeviceTransportTypeAggregate` is an aggregate. Both Aggregate and Multi-Output devices from Audio MIDI Setup count. For these, the app reads `kAudioAggregateDevicePropertyActiveSubDeviceList`.
- A device can be a volume target if it has a settable `kAudioDevicePropertyVolumeScalar`. The app tries the main element first. If that isn't settable, it uses the preferred stereo channel pair.
- Setting the volume writes the same value (0 to 1) to every target. The value shown is the average of all targets.
- Mute uses the hardware mute property where one exists. Many aggregates have none. For those, mute sets the volume to 0 and unmute restores the earlier level.
- CoreAudio property listeners watch the device list, the default output device, and each target's volume and mute. Changes made by other apps show up right away. Each listener is removed when its owner is freed.
- The UI is a SwiftUI `MenuBarExtra`. The app runs as an agent (`LSUIElement`), so it has no Dock icon.

```
Sources/MultiVolume/
  CoreAudioSupport.swift   typed wrapper over the CoreAudio HAL, listener lifetime
  AudioDevice.swift        device discovery, sub-device resolution, volume and mute
  AudioManager.swift       observable state, listeners, media-key policy
  MediaKeyMonitor.swift    CGEventTap for the volume keys (the only permissioned code)
  MenuContentView.swift    menu UI
  VolumeHUD.swift          on-screen volume overlay for the volume keys
  MultiVolumeApp.swift     entry point
Tests/MultiVolumeTests/    media-key event decoding tests
icon/                      icon master, iconset, and the scripts that produce them
Casks/multivolume.rb       Homebrew cask, updated by release.sh
```

## Limitations

- The overlay for aggregate devices is MultiVolume's own, not the system one, which comes from a private framework. It looks close but not identical.
- Every sub-device gets the same volume value. Their relative balance isn't kept, and devices with different volume curves may not sound equally loud.
- Sub-devices without a settable volume control, such as many HDMI and DisplayPort outputs, are skipped. If none of them have one, the slider is disabled.
- Only the current default output device can be controlled.
- Ad-hoc signed builds (anything built without the certificate from `make-signing-cert.sh`) get a new code hash on every rebuild, so macOS drops the Accessibility grant. To grant it again, remove the old entry under Privacy & Security, then add the app back.

## License

[MIT](LICENSE)
