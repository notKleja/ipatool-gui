import Foundation

/// A fully built ipatool argument vector. Pure data so tests can assert on it.
struct IPAToolCommand: Sendable, Equatable {
    var arguments: [String]
    var standardInput: StandardInputMode
    /// Whether ipatool should be allowed to render its interactive progress bar.
    var interactive: Bool

    init(_ arguments: [String], standardInput: StandardInputMode = .none, interactive: Bool = false) {
        self.arguments = arguments
        self.standardInput = standardInput
        self.interactive = interactive
    }
}

extension StandardInputMode: Equatable {}

/// Argument builders matching upstream `cmd/*.go`. Never assemble shell strings.
enum IPAToolCommands {
    static let jsonFormat = ["--format", "json"]

    private static func common(verbose: Bool, interactive: Bool) -> [String] {
        var flags = jsonFormat
        if verbose { flags.append("--verbose") }
        if !interactive { flags.append("--non-interactive") }
        return flags
    }

    static func version() -> IPAToolCommand {
        IPAToolCommand(["--version"])
    }

    static func authInfo(verbose: Bool = false) -> IPAToolCommand {
        IPAToolCommand(["auth", "info"] + common(verbose: verbose, interactive: false))
    }

    /// Interactive login: ipatool prompts for the password on its TTY and for a 2FA code on stdin.
    static func authLogin(email: String, verbose: Bool = false) -> IPAToolCommand {
        IPAToolCommand(["auth", "login", "--email", email] + common(verbose: verbose, interactive: true),
                       standardInput: .pseudoTerminal, interactive: true)
    }

    static func authRevoke(verbose: Bool = false) -> IPAToolCommand {
        IPAToolCommand(["auth", "revoke"] + common(verbose: verbose, interactive: false))
    }

    static func search(term: String, limit: Int, platform: AppPlatform, verbose: Bool = false) -> IPAToolCommand {
        let clamped = max(1, min(limit, platform.maximumSearchLimit))
        var arguments = ["search", "--limit", String(clamped), "--platform", platform.cliToken]
        arguments += common(verbose: verbose, interactive: false)
        arguments += ["--", term]
        return IPAToolCommand(arguments)
    }

    static func purchase(bundleID: String, platform: AppPlatform, verbose: Bool = false) -> IPAToolCommand {
        IPAToolCommand(["purchase", "--bundle-identifier", bundleID, "--platform", platform.cliToken]
                       + common(verbose: verbose, interactive: false))
    }

    static func listPurchases(page: Int, maxResults: Int, verbose: Bool = false) -> IPAToolCommand {
        IPAToolCommand(["list-purchases", "--page", String(max(1, page)), "--max-results", String(max(1, min(maxResults, 100)))]
                       + common(verbose: verbose, interactive: false))
    }

    static func listVersions(appID: Int64, verbose: Bool = false) -> IPAToolCommand {
        IPAToolCommand(["list-versions", "--app-id", String(appID)] + common(verbose: verbose, interactive: false))
    }

    static func listVersions(bundleID: String, verbose: Bool = false) -> IPAToolCommand {
        IPAToolCommand(["list-versions", "--bundle-identifier", bundleID] + common(verbose: verbose, interactive: false))
    }

    static func versionMetadata(appID: Int64, externalVersionID: ExternalVersionID, verbose: Bool = false) -> IPAToolCommand {
        IPAToolCommand(["get-version-metadata", "--app-id", String(appID), "--external-version-id", externalVersionID.rawValue]
                       + common(verbose: verbose, interactive: false))
    }

    /// Download runs interactively so ipatool renders its byte-progress bar on stdout.
    static func download(appID: Int64, platform: AppPlatform, output: URL, externalVersionID: ExternalVersionID?,
                         acquireLicense: Bool, verbose: Bool = false) -> IPAToolCommand {
        var arguments = ["download", "--app-id", String(appID), "--platform", platform.cliToken, "--output", output.path]
        if let externalVersionID { arguments += ["--external-version-id", externalVersionID.rawValue] }
        if acquireLicense { arguments.append("--purchase") }
        arguments += common(verbose: verbose, interactive: true)
        return IPAToolCommand(arguments, standardInput: .none, interactive: true)
    }
}
