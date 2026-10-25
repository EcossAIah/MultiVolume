# Security

MultiVolume asks for one sensitive permission: Accessibility (and Input
Monitoring on macOS versions that require it), used only by
`Sources/MultiVolume/MediaKeyMonitor.swift` to observe the volume up, volume
down and mute keys. The event tap subscribes to system-defined events only, so
ordinary keystrokes are never delivered to the app. Nothing is logged or
stored, and the app contains no networking code. Release builds use the
hardened runtime and do not carry the `get-task-allow` entitlement.

To report a vulnerability, use **Report a vulnerability** under this
repository's Security tab on GitHub. Please do not put details of a security
problem in a public issue. Fixes go into the latest release only.
