# Upstream analysis (ipatool)

Inspected: `github.com/majd/ipatool` at commit `a9bd16c` (main, after tag `v2.5.0`), September 2026.

## Expected engine version

- Validated against **ipatool 2.5.0**. `IPAToolVersion.recommended = 2.5.0`.
- Minimum accepted: **2.2.0** (first release with `list-versions` / `get-version-metadata`). Older binaries are reported as unsupported.
- `ipatool --version` prints Cobra's default `ipatool version X.Y.Z`; the app extracts the first `major.minor[.patch]`.

## Command surface integrated

| Command | Flags used | Notes |
|---|---|---|
| `auth login` | `--email`, `--format json` | Interactive mode (no `--non-interactive`). Password is read by `term.ReadPassword(os.Stdin)` — **requires a TTY**. 2FA code is read with `bufio` from stdin after the JSON log line `"enter 2FA code:"`. |
| `auth info` | `--format json --non-interactive` | Reads the account from the keyring. Signed-out error: `failed to get account: … could not be found in the keychain`. |
| `auth revoke` | `--format json --non-interactive` | |
| `search <term>` | `--limit`, `--platform`, `--format json --non-interactive`, `--` before the term | **Requires a signed-in account** (calls `AccountInfo()` first). visionOS is capped at 12 results. |
| `purchase` | `--bundle-identifier`, `--platform` | Refuses paid apps (`purchasing paid apps is not supported`). `alreadyOwned` reported in JSON. |
| `list-purchases` | `--page`, `--max-results` (1…100) | JSON: `count`, `totalCount`, `page`, `apps[]` with `purchaseDate`. |
| `list-versions` | `--app-id` (or `--bundle-identifier`) | JSON: `externalVersionIdentifiers: [string]`, `bundleID`. |
| `get-version-metadata` | `--app-id`, `--external-version-id` | JSON: `externalVersionID`, `displayVersion`, `releaseDate` (RFC3339). |
| `download` | `--app-id`, `--platform`, `--output`, `--external-version-id`, `--purchase`, `--format json` | Run **interactively** so the `schollz/progressbar` renders to stdout. |

Platform tokens: `iphone`, `ipad`, `appletv`, `visionos`, `macos` (`ParsePlatform` also accepts aliases; the app only emits the canonical tokens).

## JSON output shapes (from `MarshalZerologObject` / `cmd/*.go`)

```jsonc
// search
{"level":"info","count":2,"apps":[{"id":1,"bundleID":"…","name":"…","version":"…","price":0}]}
// list-purchases
{"level":"info","count":10,"totalCount":57,"page":1,"apps":[{…,"purchaseDate":"2025-08-24T01:46:40Z"}]}
// auth info / auth login success
{"level":"info","name":"First Last","email":"…","success":true}
// list-versions
{"level":"info","externalVersionIdentifiers":["870114231"],"bundleID":"…","success":true}
// get-version-metadata
{"level":"info","externalVersionID":"870114231","displayVersion":"7.4.1","releaseDate":"2026-08-18T14:00:00Z","success":true}
// download
{"level":"info","output":"/path/file.ipa","purchased":false,"success":true}
// purchase
{"level":"info","alreadyOwned":false,"success":true}
// any failure (exit status 1)
{"level":"error","error":"license is required","success":false}
```

All lines go to **stdout** (zerolog `SyncWriter(os.Stdout)`); `--verbose` adds `"level":"debug"` lines that the parser skips. Every line is a JSON object; decoders ignore unknown keys and treat most fields as optional.

## Authentication behavior

1. `auth login` logs `enter password:` (JSON line) then calls `term.ReadPassword` on fd 0 → the app allocates a **pseudo-terminal** (`openpty`, `ECHO` off) for stdin and writes the password once the prompt appears.
2. ipatool logs `preparing authentication; the first login may take a few minutes`.
3. If Apple answers with `MZFinance.BadLogin.Configurator_message` and no code was supplied, ipatool returns `ErrAuthCodeRequired`; in interactive mode it retries once after logging `enter 2FA code:` and reading a line from stdin.
4. Success prints the account JSON line and exit 0. Any failure prints an `error` line and exits 1; the process cannot be resumed, so the GUI restarts the flow from the credentials step.

The session (password token, DSID, storefront, and — upstream design — the password itself) is stored by ipatool in the keyring `ipatool-auth.service` (macOS Keychain) so that expired tokens can be refreshed. Cookies live in `~/.ipatool/cookies`. The GUI never reads or writes those.

## Download behavior

- Version string for the default filename comes from `bundleShortVersionString` in the download response; ipatool names files `bundleID_id_version.ipa|pkg` when `--output` is a directory or empty, otherwise uses `--output` verbatim (writes `<output>.tmp` first, then applies sinf patches and renames).
- macOS platform produces a `.pkg`; all others an `.ipa`. tvOS/visionOS latest downloads resolve an external version id internally.
- `ErrLicenseRequired` (failure type 9610) is retried with a purchase only when `--purchase` is set; otherwise it fails with `license is required`.
- Progress: `progressbar.NewOptions64(…OptionShowBytes…)` writes `downloading NN% |…| (x/y MB, …)` frames separated by `\r` to stdout, only in interactive mode. The GUI parses the percentage and otherwise shows an indeterminate bar.

## Known integration limitations

- Search needs authentication — Discover shows a sign-in empty state when signed out.
- Paid apps can't be acquired through ipatool; the GUI explains this and still allows downloads for already-owned paid apps.
- The file-based keyring passphrase (`--keychain-passphrase`) is only relevant on Linux; on macOS ipatool uses the login Keychain and may show a system prompt the first time.
- Exact error strings are matched heuristically; unknown errors are surfaced with the raw message under "Show Details".
- `list-versions` / `get-version-metadata` are documented upstream for iOS apps; results for other platforms depend on the App Store response.
