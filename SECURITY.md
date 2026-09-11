# Security policy

## What this app handles

IPATool for Mac is a front end for `ipatool`. The only secrets that pass through it are the Apple Account password and one-time verification code typed into the Sign In sheet. Both are handed to ipatool over a private pseudo-terminal and zeroed in memory immediately after. Nothing sensitive is written to UserDefaults, files, logs, crash metadata or diagnostic reports.

Session state (password token, storefront, DSID) is created and stored by ipatool itself in the macOS Keychain under `ipatool-auth.service`. This app never reads or modifies it. **Sign Out** runs `ipatool auth revoke`.

## Reporting a vulnerability

Open a GitHub issue with the label `security`, or, for anything that would put user credentials at risk, use GitHub's private vulnerability reporting on this repository. Please include the app version, the ipatool version (`ipatool --version`) and steps to reproduce. Never paste real credentials, tokens or Keychain contents into a report.

## Verifying a release

Release builds are produced with `xcodebuild -configuration Release` from the tagged commit, ad-hoc signed and not notarized. To verify, build the tag yourself (see *Build from source* in the README) and compare `codesign -dvv` / `shasum -a 256` of the main executable, or simply run the build you made.
