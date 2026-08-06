import ArgumentParser

struct Work: ParsableCommand {
    // Single source of truth for the release version. Bumped by `vrsn -k
    // version` (see Makefile) and read by the release workflow.
static let version = "0.3.0"

    static let configuration = CommandConfiguration(
        commandName: "work",
        abstract: "Worktree, tmux session, and pluggable cloud-devbox manager",
        version: Work.version,
        subcommands: [
            Start.self,
            Term.self,
            Finish.self,
            RemoteGroup.self,
        ]
    )
}
