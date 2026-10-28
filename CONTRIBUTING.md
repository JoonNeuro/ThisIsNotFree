# Contributing

Build with `zsh Scripts/build-app.sh` and run all checks with `zsh Scripts/test.sh`.
The project requires macOS 14.2 or newer and Xcode Command Line Tools with Swift 5.10 or newer.

Keep tools optional and keep the UI in English. Request a system permission only when a user enables the feature that needs it. Network requests belong to the GitHub update checker; system measurements and audio remain local.

For bug reports, include the macOS version, Mac model, enabled module, expected behavior, and reproduction steps. For display or audio issues, include the connection type and device model. Avoid sharing recordings, private menu contents, or credentials.

Changes to audio callbacks must keep allocations, locks, filesystem operations, and network requests outside the real-time callback. Changes to hiding, dimming, and power assertions must restore normal behavior when disabled or on a clean exit.
