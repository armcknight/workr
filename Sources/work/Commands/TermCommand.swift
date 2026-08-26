import Foundation

/// Port of src/cmd/term.rs.
enum TermCommand {
    static func run(_ cfg: Config) throws {
        // Check repo membership directly. Previously this inferred it from an
        // empty `branch --show-current`, which misreported any detached HEAD —
        // including the middle of a rebase — as "not in a git repository".
        guard Git.inRepo() else {
            throw WorkError("Not in a git repository")
        }
        let branch = try Git.sessionBranch()

        // Terminal window naming is deliberately NOT done here. The shell owns
        // the title (fish's fish_title emits cwd + branch on every prompt
        // redraw, overwriting anything set out-of-band from this process).
        let pwd = FileManager.default.currentDirectoryPath
        let session = Tmux.sessionName(pwd: pwd, branch: branch)

        if Tmux.hasSession(session) {
            try Tmux.attachSession(session)
        } else {
            try Tmux.tmuxinatorStart(config: cfg.tmux.tmuxinatorConfig, sessionName: session)
        }
    }
}
