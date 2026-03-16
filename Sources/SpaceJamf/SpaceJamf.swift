import ArgumentParser

@main
struct SpaceJamf: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spacejamf",
        abstract: "macOS diagnostics for Jamf + Active Directory environments",
        discussion: """
        Runs targeted diagnostic commands, scrubs sensitive data, and sends structured
        output to Claude for root-cause analysis. Renders findings as a rich terminal
        report or shareable self-contained HTML file.
        """,
        version: "0.1.0",
        subcommands: [DiagnoseCommand.self, ReportCommand.self],
        defaultSubcommand: DiagnoseCommand.self
    )
}
