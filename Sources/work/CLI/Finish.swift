import ArgumentParser

struct Finish: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "finish",
        abstract: "Tear down a worktree (or, with --provider, a cloud devbox)."
    )

    @Option(name: [.short, .long], help: "Tear down the named remote provider's devbox instead of a local worktree.")
    var provider: String?

    @Argument(help: "Branch name (or workspace / box slug).")
    var branch: String

    func run() throws {
        let cfg = try Config.load()
        if let provider {
            try FinishCommand.runRemote(self, cfg, provider: provider)
        } else {
            try FinishCommand.runLocal(self, cfg)
        }
    }
}
