import ArgumentParser

/// Output format accepted by both `diagnose` and `report` subcommands.
enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case terminal
    case html
}
