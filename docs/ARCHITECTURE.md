# Architecture

```
IPAToolGUI/
  App/            IPAToolGUIApp (scenes, commands), AppState (root wiring)
  Models/         AppPlatform, AppStoreApp, PurchasedPage, Account, AppVersion,
                  IPAToolVersion, DownloadItem/DownloadRequest, AppMetadata
  Services/       ProcessRunner, IPAToolCommand (argv builders), IPAToolService (+ LoginAttempt actor),
                  MockIPAToolService (+ Fixtures), IPAToolLocator, AuthenticationService,
                  DownloadManager, DownloadHistoryStore, AppMetadataService, SettingsStore
  Features/       Main (window, sidebar, engine-missing), Discover, AppDetail, Versions,
                  Library, Downloads, Authentication, Settings
  Shared/         Components (icon, pickers, empty states, error alert), Errors (EngineError,
                  ErrorClassifier), Utilities (redaction, filenames, JSON-lines parsing, PTY, UTF-8)
IPAToolGUITests/  process runner, argv construction, JSON decoding, error classification,
                  redaction, filenames, download-state transitions, view models, fake-engine integration
```

## Layers

```
SwiftUI views ──▶ @Observable view models (MainActor) ──▶ IPAToolServing (Sendable)
                                                              │
                        DownloadManager / AuthenticationService (MainActor state)
                                                              │
                                      IPAToolService ──▶ ProcessRunning ──▶ Process (argv only)
                                                              │
                                              IPAToolOutput (JSON-lines) + ErrorClassifier
```

- **ProcessRunner**: launches the configured executable with an argument array, captures stdout/stderr through readability handlers (no blocking reads, no deadlocks), decodes UTF-8 incrementally, optionally attaches a pipe or a pseudo-terminal to stdin, supports SIGTERM/SIGKILL and task cancellation, and emits a redacted `DiagnosticEntry` per run.
- **IPAToolService**: one method per user intention; builds `IPAToolCommand`s, runs them, decodes the last non-debug JSON line, converts failures into `EngineError`.
- **AppState**: owns settings, engine detection status, authentication, the download manager and metadata provider; injected via `.environment`.

## Authentication state machine

```
signedOut ──Sign In──▶ credentials ──Continue──▶ authenticating
    ▲                                              │  "enter 2FA code:" line
    │ failure (any error; process exits 1)         ▼
    └───────────────────────────────────── verification ──Verify──▶ verifying ──success──▶ signedIn
Cancel at any step: SIGTERM the child, zero the password buffer.
```

## Download state machine

```
queued ─▶ preparing ─▶ [acquiringLicense] ─▶ downloading ─▶ completed
   │           │               │                  │
   └───────────┴───────────────┴──────────────────┴─▶ cancelled (SIGTERM, .tmp removed)
               └───────────────┴──────────────────┴─▶ failed (EngineError kind + redacted details)
failed(licenseRequired) ─"Get & Download"─▶ re-enqueued with acquireLicense = true
```
`DownloadManager` runs at most `maxConcurrent` (1…4) ipatool processes; history is persisted to `~/Library/Application Support/IPATool/downloads.json`; in-flight items become `cancelled` on relaunch.

## Error model

`EngineErrorKind` (20 cases) + `EngineError { kind, rawMessage, diagnostics }`. `ErrorClassifier` maps ipatool's `error` field (or stderr) to a kind by substring rules taken from upstream sources; UI shows title/message per kind and keeps the raw text under **Show Details**. Secrets are removed by `SecretRedactor` before anything is stored or displayed.

## Metadata enrichment

`AppMetadataService` (actor) batches numeric App Store IDs into `itunes.apple.com/lookup`, throttles to ≥300 ms between requests, coalesces in-flight lookups, and caches for 24 h in `~/Library/Caches/dev.ipatoolgui.IPAToolGUI/metadata.json`. Views fall back to ipatool's data whenever it fails.
