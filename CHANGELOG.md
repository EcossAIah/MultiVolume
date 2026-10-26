# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] - 2026-10-26

### Fixed

- The menu panel now shrinks back to fit its content after the permission
  warning goes away, instead of leaving an empty strip of window.
- No focus ring on the mute button when the panel opens.
- ⇧⌥ fine volume steps now work. The modifiers were read from the live
  keyboard state instead of the key event, so they were missed.

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
