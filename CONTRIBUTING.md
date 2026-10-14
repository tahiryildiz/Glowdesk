# Contributing to Glowdesk

## Build from source

Requires macOS 14 or later and the Xcode Command Line Tools (Swift 5.9+, `xcode-select --install`).

```sh
bash scripts/build.sh
open dist/Glowdesk.app
```

Local builds are signed ad hoc, so macOS may ask you to confirm the first time you open them.

## Checks

These run without a bridge:

```sh
dist/Glowdesk.app/Contents/MacOS/Glowdesk --self-check
```

Debug builds render every tab with demo data, which is also how the README images are made:

```sh
swift build && .build/debug/Glowdesk --snapshot /tmp/glowdesk-shots
swift scripts/make-screenshots.swift /tmp/glowdesk-shots/en docs
```

The app icon is drawn by `swift scripts/make-icon.swift Assets`.

## Reporting a problem

Launch with logging, reproduce the problem, then attach the log:

```sh
open /Applications/Glowdesk.app --args --log
```

The log is written to `~/Library/Application Support/Glowdesk/debug.log`. It records commands, replies and live events, never the app key. Remove your bridge's IP address before posting it publicly. Please include your macOS version and bridge model.

## Translations

All interface text lives in `Sources/Glowdesk/L10n.swift`. English is the key; add a dictionary for your language and a case in `AppLanguage`.

## How it works

- Hue's official local API (CLIP v2) and its live event stream; nothing goes through the cloud.
- The bridge's TLS certificate is pinned on first pairing. The app key and the pin are stored in the Keychain, keyed by bridge ID.
- Slider and scroll updates are coalesced per light or group to stay under the bridge's rate limits.
- Screen sync scales the screen down to 64×36 pixels a few times per second and never saves it.
- One SwiftPM target, no third-party dependencies: SwiftUI, Network, ScreenCaptureKit, CryptoKit.

## Releasing

`VERSION=1.0.1 bash scripts/release.sh` builds, signs with a Developer ID, notarizes and staples the app and writes `dist/Glowdesk-1.0.1.zip`. The script header lists the one-time setup.

## License

MIT, see [LICENSE](LICENSE). Third-party code and trademarks are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
