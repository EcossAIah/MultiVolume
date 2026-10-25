# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/EcossAIah/MultiVolume/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/EcossAIah/MultiVolume/releases/tag/v1.0.0
