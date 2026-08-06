import ArgumentParser

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Create a worktree (or, with --provider, a cloud devbox) and start a session."
    )

    @Option(name: [.short, .long], help: "Provision via the named remote provider plugin instead of a local worktree.")
    var provider: String?

    @Flag(name: .long, help: "Skip starting a tmux session (for headless / autonomous use).")
    var headless = false

    @Option(name: .long, help: "Prompt file to pipe into `claude` after creating the worktree (local --headless mode).")
    var promptFile: String?

    @Option(name: .long, help: "Log file to capture Claude output (local --headless mode, requires --prompt-file).")
    var logFile: String?

    @Option(name: .customLong("param"), help: ArgumentHelp("Provider param override as key=value, forwarded to the plugin. Repeatable.", valueName: "KEY=VALUE"))
    var param: [String] = []

    @Argument(help: "Branch name. For --provider, must include a Linear ticket ID, e.g. user/team-123-slug.")
    var branch: String

    func run() throws {
        let cfg = try Config.load()
        if let provider {
            try StartCommand.runRemote(self, cfg, provider: provider)
        } else {
            try StartCommand.runLocal(self, cfg)
        }
    }
}
