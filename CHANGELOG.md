# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The volume overlay is interactive: hovering shows a slider, the left
  speaker mutes, the right speaker sets full volume, and × closes it. It
  uses Liquid Glass on macOS 26 and later.
- The volume keys play the system feedback sound when "Play feedback when
  volume is changed" is on.
- Open at Login toggle in the menu.
- Device Balance: a saved volume share for each device in a multi-output
  device. The volume keys scale all of them and keep the balance.
- Create, edit and delete multi-output devices from the menu.
- An ⓘ next to devices without a volume control explains why, on hover.

### Changed

- The menu uses the standard macOS text styles throughout.

## [1.1.1] - 2026-10-27

### Fixed

- The menu panel now shrinks back to fit its content after the permission
  warning goes away, instead of leaving an empty strip of window.
- No focus ring on the mute button when the panel opens.
- Devices that hide themselves from the Sound menu, such as Zoom's
  `ZoomAudioDevice`, no longer appear in the output list.

### Removed

- ⇧⌥ fine volume steps. They did not work reliably.
- The "Media keys active" note in the menu. The media keys section now only
  appears when a permission is missing.

### Added

- `brew uninstall --zap --cask multivolume` also removes the settings file,
  and the README explains how to remove the privacy permission entries.

## [1.1.0] - 2026-10-26

### Added

- On-screen volume indicator when the volume keys change an aggregate
  device, since the system indicator does not appear for keys this app
  handles.
- Homebrew cask: install with `brew install --cask multivolume`, update with
  `brew upgrade --cask multivolume`.
- `make-signing-cert.sh` and `release.sh` for signed builds and one-command
  releases.

### Changed

- Releases are signed with a fixed self-signed certificate instead of
  ad-hoc, so macOS keeps the Accessibility and Input Monitoring grants across
  updates. Updating from 1.0.0 needs those grants once more; after that they
  persist. The app is still not notarized.

## [1.0.0] - 2026-10-25

### Added

- Menu bar volume slider and mute for aggregate and multi-output devices,
  applied to every active sub-device with a settable volume control.
- Hardware mute where available, with a volume-zero fallback for devices
  that expose no mute control.
- −10% / −5% / +5% / +10% step buttons.
- Output device list that switches the system default output.
- Live updates from CoreAudio property listeners.
- Volume keys (F10/F11/F12) for aggregate devices via a `CGEventTap` limited to
  system-defined events, with ⇧⌥ for fine steps. Other devices keep native
  handling.
- Permission status for Accessibility and Input Monitoring in the menu, with
  automatic retry once access is granted.
- `build.sh`: universal build with no absolute build paths in the binary,
  hardened-runtime signing, self-verification of the signed bundle, and a
  release zip.

[Unreleased]: https://github.com/EcossAIah/MultiVolume/compare/v1.1.1...HEAD
[1.1.1]: https://github.com/EcossAIah/MultiVolume/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/EcossAIah/MultiVolume/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/EcossAIah/MultiVolume/releases/tag/v1.0.0
