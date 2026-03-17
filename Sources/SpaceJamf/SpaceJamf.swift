import ArgumentParser

@main
struct SpaceJamf: AsyncParsableCommand, Sendable {
    static let configuration = CommandConfiguration(
        commandName: "spacejamf",
        abstract: "macOS diagnostics for Jamf + Active Directory environments",
        discussion: """
        Runs targeted diagnostic commands, scrubs sensitive data, and sends structured
        output to Claude for root-cause analysis. Renders findings as a rich terminal
        report or shareable self-contained HTML file.
        """,
        // SJ1: Keep version in sync with the git tag and CHANGELOG.md.
        // TODO: inject from build settings (e.g. generated Swift constant) when
        // release automation is in place; for now keep in sync manually.
        version: "0.1.0",
        subcommands: [DiagnoseCommand.self, ReportCommand.self],
        // SJ-2: DiagnoseCommand is the default so `spacejamf` runs a full diagnosis
        // when invoked without a subcommand (common usage pattern).
        defaultSubcommand: DiagnoseCommand.self
    )
}
