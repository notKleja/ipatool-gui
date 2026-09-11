# IPATool for Mac

A native macOS front end for [ipatool](https://github.com/majd/ipatool) by Majd Alfhaily. Search the App Store, browse the apps your Apple Account has acquired, download the latest or a historical build for iPhone, iPad, Apple TV, Apple Vision or Mac, and manage those downloads — without touching a terminal.

IPATool is a GUI over legitimate ipatool functionality. It does **not** decrypt apps, strip FairPlay, bypass App Store licensing or payment, or bypass Apple Account authentication.

## Requirements

- macOS 15 Sequoia or later (Apple silicon or Intel)
- [ipatool](https://github.com/majd/ipatool) **2.5.0 or newer** (2.2.0 is the minimum accepted)
- Xcode 16 or newer to build from source

## Installing the engine

```bash
brew install ipatool
```

IPATool looks for the binary in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/bin`, `/opt/local/bin` and `$PATH`. You can also pick any executable with **Settings → ipatool → Select Binary…**. The app runs `ipatool --version` to validate it and shows `ipatool 2.x.x · Ready`, or a compatibility warning.

If ipatool is missing, the empty state offers **Install with Homebrew…** (runs `brew install ipatool` only after you confirm, with live output) or a link to the GitHub releases page. The app never installs software without that confirmation.

## Features

- **Discover** – App Store search with a platform picker, debounced queries, icons/developers from Apple's public lookup service when available.
- **App detail** – bundle ID and App ID (copyable), version, platform, price, description, screenshots, App Store link, Download Latest / Get & Download / Version History.
- **Version History** – historical builds shown as *Version · Released · Download*; external version IDs resolved lazily with bounded concurrency and hidden unless you ask for them.
- **Library** – `list-purchases` with local filtering, newest acquisitions first, Load More / infinite scrolling.
- **Downloads** – real queue (1–4 concurrent processes), determinate progress when ipatool reports it, cancel, retry, Reveal in Finder, Open Containing Folder, Copy Path, Download Again, Remove from History (the file is never deleted). History survives relaunches.
- **Sign in** – native two-step sheet (Apple Account + password, then verification code).
- **Settings** – download folder, reveal after download, filename-conflict policy, default platform, concurrency, engine binary, verbose logging, account, diagnostics.

## Authentication and where credentials live

Sign In runs `ipatool auth login --email <email>` interactively. The password is written to a private pseudo-terminal that ipatool reads with `term.ReadPassword`; it is **never** placed on the command line, logged, persisted or included in diagnostics. The verification code is written once to the same terminal and discarded. Buffers are zeroed after use.

ipatool — not this app — stores the resulting App Store session in the macOS login Keychain under `ipatool-auth.service` (upstream keeps the password there so it can refresh expired tokens) and cookies in `~/.ipatool/cookies`. The app never reads or edits those. macOS may show a Keychain permission dialog the first time ipatool runs from this app; choose *Always Allow* to avoid repeated prompts.

**Sign Out** runs `ipatool auth revoke`, which deletes ipatool's stored App Store session. It does not sign you out of iCloud or your Mac.

## Package encryption / DRM

Packages downloaded through ipatool are App Store packages: iOS-family downloads are `.ipa` files, macOS downloads are `.pkg`. They remain tied to the Apple Account that acquired them and may still be FairPlay-protected. This app doesn't change that.

## Known limitations

- Searching requires a signed-in account (an upstream ipatool constraint).
- ipatool can only acquire **free** apps. Paid apps must be bought in the App Store first; afterwards they download normally.
- Download progress is parsed from ipatool's progress bar; when a build doesn't render it, the app shows an honest indeterminate "Downloading…".
- Version history is provided by the App Store's iOS endpoints; other platforms may return fewer results.
- Error mapping is heuristic; anything unrecognized is shown as "Something Went Wrong" with the raw message under *Show Details*.

## Sandboxing

The app is **not** App-Sandboxed. A sandboxed child process would inherit the sandbox and ipatool could not access `~/.ipatool`, the Keychain item it owns, or user-chosen download folders. Hardened Runtime is enabled. Because there is no sandbox, folder selections are stored as plain paths rather than security-scoped bookmarks.

## Download

Grab `IPAToolGUI.app.zip` from the [latest release](https://github.com/notKleja/ipatool-gui/releases/latest), unzip, and move `IPAToolGUI.app` to `/Applications`. The release build is ad-hoc signed and not notarized, so macOS Gatekeeper will block the first launch: right-click the app → **Open** → **Open**, or run

```bash
xattr -d com.apple.quarantine /Applications/IPAToolGUI.app
```

If you'd rather not trust a pre-built binary, build from source below — it takes about a minute.

## Build from source

1. Install Xcode 16 or newer from the Mac App Store and open it once so the command-line tools are set up.
2. Clone the repository:
   ```bash
   git clone https://github.com/notKleja/ipatool-gui.git
   cd ipatool-gui
   ```
3. Build a Release app:
   ```bash
   xcodebuild -project IPAToolGUI.xcodeproj -scheme IPAToolGUI -configuration Release build
   ```
   The app lands in Xcode's DerivedData; copy it somewhere useful:
   ```bash
   cp -R "$(xcodebuild -project IPAToolGUI.xcodeproj -scheme IPAToolGUI -configuration Release -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/IPAToolGUI.app" /Applications/
   ```
4. Or open `IPAToolGUI.xcodeproj` in Xcode, select the `IPAToolGUI` scheme and press ⌘R.

The project has no third-party dependencies and no package resolution step. It uses ad-hoc signing by default; set your team under *Signing & Capabilities* if you want a Developer ID build.

## Security

- **Your Apple Account password never touches the command line, logs, disk or diagnostics.** It is written once to a private pseudo-terminal that ipatool reads, then the buffer is zeroed.
- **Verification codes are never stored.** They are written once to ipatool and discarded.
- **No credentials are persisted by this app.** ipatool alone keeps its App Store session in the macOS Keychain (`ipatool-auth.service`); the app never reads, edits or exports it.
- **No shell interpolation.** Every ipatool invocation is an argument array passed directly to the executable; user input can't inject commands.
- **No telemetry, no analytics.** The only network calls are ipatool's own App Store traffic and optional icon/description lookups against Apple's public `itunes.apple.com/lookup`, keyed by App Store ID only.
- **Nothing is installed without consent.** The Homebrew installer runs `brew install ipatool` only after you confirm in a dialog, and shows its full output.
- **Diagnostics are redacted.** Command lines, JSON output and error text pass through a redactor that masks passwords, tokens, codes and passphrases before anything is recorded or copied.
- **No DRM circumvention.** Downloaded packages remain App Store packages tied to your account; the app doesn't decrypt, resign or bypass licensing.

Found a problem? Open an issue or see [SECURITY.md](SECURITY.md).

Run the tests:

```bash
xcodebuild -project IPAToolGUI.xcodeproj -scheme IPAToolGUI -destination 'platform=macOS' test
```

Tests cover the process runner (pipes, PTY, cancellation, large output), argument construction, JSON decoding for every command, error classification, secret redaction, filename sanitizing, download-state transitions, the view models, and an integration suite that drives the real service against a shell script speaking ipatool's stdout protocol. No test contacts the App Store.

## Development notes

- Swift 6 language mode with complete concurrency checking; `@Observable` view models on the main actor; services are `Sendable`.
- `MockIPAToolService` and `Fixtures` back every SwiftUI preview (signed-out, signed-in, results, empty search, library, version history, active/failed downloads).
- See `docs/UPSTREAM.md` for the upstream analysis and `docs/ARCHITECTURE.md` for the layer/state-machine overview.

## Troubleshooting

| Symptom | What to check |
|---|---|
| "ipatool Is Required" | Install with Homebrew or choose the binary in Settings → ipatool. GUI apps see a minimal `$PATH`; the known Homebrew locations are checked explicitly. |
| Sign-in never finishes | The first login can take a minute while ipatool prepares its session. Check that a macOS Keychain dialog isn't waiting behind the window. |
| "Sign In Required" after being signed in | The session expired or was revoked. Sign in again. |
| "App Not Acquired" | Use **Get & Download** (free apps) or buy the app in the App Store first. |
| "Not Available in Your Storefront" | The app isn't sold in the storefront tied to your Apple Account. |
| Download stuck at "Downloading…" with no percentage | ipatool didn't report byte progress for this build; the process is still running. Cancel terminates it cleanly. |
| Need details for a bug report | Settings → Advanced → Copy Diagnostic Report (redacted; never includes credentials). |
