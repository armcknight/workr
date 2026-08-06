import Foundation
import WorkRemoteContract

/// Port of src/cmd/start.rs, provider paths now delegated to a plugin.
enum StartCommand {
    static func runLocal(_ args: Start, _ cfg: Config) throws {
        guard Git.inRepo() else {
            throw WorkError("Not in a git repository")
        }

        let worktreePath = cfg.worktree.pathTemplate.replacingOccurrences(of: "{branch}", with: args.branch)
        let fm = FileManager.default

        if isDirectory(worktreePath) {
            if args.headless {
                print("Worktree \(worktreePath) already exists, reusing")
            } else {
                throw WorkError("Worktree \(worktreePath) already exists")
            }
        } else {
            print("Creating worktree: \(worktreePath)")
            if Git.branchExists(args.branch) {
                print("Branch \(args.branch) already exists, using existing branch")
                try Git.worktreeAdd(worktreePath, args.branch)
            } else {
                print("Creating new branch: \(args.branch)")
                try Git.worktreeAddNewBranch(worktreePath, args.branch)
            }

            for file in cfg.worktree.symlinkFiles {
                try linkIntoWorktree(file, worktreePath)
            }

            if !cfg.worktree.postCreateCommand.isEmpty {
                print("Running post-create command: \(cfg.worktree.postCreateCommand)")
                _ = try? Shell.run("sh", ["-c", cfg.worktree.postCreateCommand], currentDirectory: worktreePath)
            }
        }

        if args.headless {
            if let promptFile = args.promptFile {
                try runClaudeHeadless(promptFile: promptFile, logFile: args.logFile, worktree: worktreePath)
            }
        } else {
            if !fm.changeCurrentDirectoryPath(worktreePath) {
                throw WorkError("changing into \(worktreePath)")
            }
            try TermCommand.run(cfg)
        }
    }

    /// Provision via a remote-provider plugin: fetch ticket + build prompt in
    /// core, then hand the provider-specific work to the plugin's `start`.
    static func runRemote(_ args: Start, _ cfg: Config, provider: String) throws {
        let runner = try PluginRunner.resolve(provider: provider, config: cfg)

        guard let ticketID = extractTicketID(args.branch) else {
            throw WorkError("branch '\(args.branch)' contains no Linear ticket ID.\nExpected format: <user>/<team>-<number>-<slug> (e.g. user/team-123-add-widget)")
        }

        print("Fetching Linear ticket \(ticketID)...")
        let ticket = try Linear.getTicket(ticketID)

        let describe = try runner.describe()
        if describe.contract != WorkRemoteContract.version {
            throw WorkError("remote '\(runner.provider)' implements contract \(describe.contract), core expects \(WorkRemoteContract.version)")
        }

        let commandsDir = expandTilde(cfg.prompt.slashCommandsDir)
        let slash = try Prompt.loadInlinedSections(cfg.prompt, commandsDir: commandsDir)
        let promptText = Prompt.build(ticket: ticket, branch: args.branch, workspacePaths: describe.workspacePaths, sections: slash)

        if cfg.linear.autoUpdateState {
            print("Updating Linear ticket \(ticketID) state to '\(cfg.linear.stateName)'...")
            do {
                try Linear.updateState(ticketID, cfg.linear.stateName)
            } catch {
                ewrite("  warning: \(error)")
            }
        }

        try runner.start(branch: args.branch, prompt: promptText, repos: cfg.project.repos, params: parseParams(args.param))

        print("Done. Tail the session with: work remote log --provider \(runner.provider) \(args.branch)")
    }

    // MARK: - Helpers

    /// Extract a Linear ticket ID (`[a-z]+-[0-9]+`, case-insensitive), uppercased.
    static func extractTicketID(_ branch: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "[a-z]+-[0-9]+", options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(branch.startIndex..<branch.endIndex, in: branch)
        guard let m = re.firstMatch(in: branch, range: range), let r = Range(m.range, in: branch) else {
            return nil
        }
        return String(branch[r]).uppercased()
    }

    /// Parse repeatable `--param key=value` into a dict, warning on malformed.
    static func parseParams(_ raw: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for entry in raw {
            guard let eq = entry.firstIndex(of: "=") else {
                ewrite("warning: ignoring malformed --param `\(entry)` (expected key=value)")
                continue
            }
            out[String(entry[entry.startIndex..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return out
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func isFile(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }

    private static func linkIntoWorktree(_ rel: String, _ worktreePath: String) throws {
        let fm = FileManager.default
        guard isFile(rel) else {
            ewrite("warning: no \(rel) found in repo root — worktree will not have one")
            return
        }
        let abs = URL(fileURLWithPath: rel).resolvingSymlinksInPath().path
        let dest = URL(fileURLWithPath: worktreePath).appendingPathComponent(rel).path
        let parent = (dest as NSString).deletingLastPathComponent
        do {
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
        } catch {
            throw WorkError("creating \(parent): \(error.localizedDescription)")
        }
        try? fm.removeItem(atPath: dest)
        do {
            try fm.createSymbolicLink(atPath: dest, withDestinationPath: abs)
        } catch {
            throw WorkError("symlinking \(rel) into worktree: \(error.localizedDescription)")
        }
        print("Symlinked \(rel)")
    }

    private static func runClaudeHeadless(promptFile: String, logFile: String?, worktree: String) throws {
        guard let promptHandle = FileHandle(forReadingAtPath: promptFile) else {
            throw WorkError("opening prompt file \(promptFile)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "-p", "--dangerously-skip-permissions"]
        process.currentDirectoryURL = URL(fileURLWithPath: worktree)
        process.standardInput = promptHandle

        if let logFile {
            guard FileManager.default.createFile(atPath: logFile, contents: nil),
                  let logHandle = FileHandle(forWritingAtPath: logFile)
            else {
                throw WorkError("creating log file \(logFile)")
            }
            process.standardOutput = logHandle
            process.standardError = logHandle
        }

        do {
            try process.run()
        } catch {
            throw WorkError("failed to launch claude: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw WorkError("claude exited with status \(process.terminationStatus)")
        }
    }
}
