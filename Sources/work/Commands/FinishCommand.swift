import Foundation

/// Port of src/cmd/finish.rs, provider teardown now delegated to a plugin.
enum FinishCommand {
    static func runLocal(_ args: Finish, _ cfg: Config) throws {
        guard Git.inRepo() else {
            throw WorkError("Not in a git repository")
        }

        let worktreePath = cfg.worktree.pathTemplate.replacingOccurrences(of: "{branch}", with: args.branch)

        if isDirectory(worktreePath) {
            print("Removing .env files from worktree...")
            _ = try? Git.worktreeClean(worktreePath)
        }

        print("Fetching latest changes...")
        _ = try? Git.fetch()

        if isDirectory(worktreePath) {
            print("Removing worktree: \(worktreePath)")
            do {
                try Git.worktreeRemove(worktreePath)
            } catch {
                ewrite("warning: \(error)")
            }
        } else {
            print("Worktree \(worktreePath) does not exist")
        }

        if Git.branchExists(args.branch) {
            print("Deleting branch: \(args.branch)")
            try Git.branchDeleteForce(args.branch)
        } else {
            print("Branch \(args.branch) does not exist")
        }

        if FileManager.default.fileExists(atPath: worktreePath) {
            let full = URL(fileURLWithPath: worktreePath).resolvingSymlinksInPath().path
            let session = Tmux.sessionName(pwd: full, branch: args.branch)
            if Tmux.hasSession(session) {
                print("Killing tmux session: \(session)")
                _ = try? Tmux.killSession(session)
            }
        }

        print("Worktree cleanup complete")
    }

    /// Tear down the remote devbox via the plugin, then clean up the local
    /// branch (generic).
    static func runRemote(_ args: Finish, _ cfg: Config, provider: String) throws {
        let runner = try PluginRunner.resolve(provider: provider, config: cfg)

        let branchName: String? = args.branch.contains("/")
            ? args.branch
            : (Git.inRepo() ? Git.findBranchBySuffix(args.branch) : nil)

        try runner.finish(branch: args.branch)
        try localBranchCleanup(branchName)
    }

    /// Checkout default branch, fast-forward, delete the topic branch.
    static func localBranchCleanup(_ branchName: String?) throws {
        if !Git.inRepo() {
            print("Not in a git repository; skipping local branch cleanup.")
            return
        }
        guard let def = Git.defaultBranch() else {
            print("Could not determine default branch; skipping checkout/pull.")
            return
        }
        print("Checking out \(def) and fast-forwarding...")
        try Git.checkout(def)
        _ = try? Git.pullFFOnly()

        if let branch = branchName {
            if Git.branchExists(branch) {
                print("Deleting local branch '\(branch)'...")
                _ = try? Git.branchDeleteForce(branch)
            } else {
                print("Local branch '\(branch)' not present; nothing to delete.")
            }
        }
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
