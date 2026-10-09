import ArgumentParser

struct Start: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "start",
    abstract: "Create a worktree (or, with --provider, a cloud devbox) and start a session."
  )

  @Option(
    name: [.short, .long],
    help: "Provision via the named remote provider plugin instead of a local worktree.")
  var provider: String?

  @Flag(name: .long, help: "Skip starting a tmux session (for headless / autonomous use).")
  var headless = false

  @Option(
    name: .long,
    help: "Prompt file to pipe into `claude` after creating the worktree (local --headless mode).")
  var promptFile: String?

  @Option(
    name: .long,
    help: "Log file to capture Claude output (local --headless mode, requires --prompt-file).")
  var logFile: String?

  @Option(
    name: .long,
    help: ArgumentHelp(
      "Start the headless Claude session with this ID, so a caller can resume it later.",
      valueName: "UUID"))
  var sessionId: String?

  @Option(
    name: .long,
    help: ArgumentHelp(
      "Resume the headless Claude session with this ID instead of starting one. The prompt file is sent as the next message, and the log file is appended to.",
      valueName: "UUID"))
  var resume: String?

  @Option(
    name: .customLong("param"),
    help: ArgumentHelp(
      "Provider param override as key=value, forwarded to the plugin. Repeatable.",
      valueName: "KEY=VALUE"))
  var param: [String] = []

  @Argument(
    help: "Branch name. For --provider, must include a Linear ticket ID, e.g. user/team-123-slug.")
  var branch: String

  func validate() throws {
    if sessionId != nil || resume != nil {
      if sessionId != nil && resume != nil {
        throw ValidationError("--session-id and --resume are mutually exclusive")
      }
      if provider != nil || !headless || promptFile == nil {
        throw ValidationError(
          "--session-id and --resume need local --headless mode with --prompt-file")
      }
    }
  }

  /// The Claude session a headless run starts or resumes, if the caller named one.
  var claudeSession: ClaudeSession? {
    if let sessionId { return .start(sessionId) }
    if let resume { return .resume(resume) }
    return nil
  }

  func run() throws {
    let cfg = try Config.load()
    if let provider {
      try StartCommand.runRemote(self, cfg, provider: provider)
    } else {
      try StartCommand.runLocal(self, cfg)
    }
  }
}

/// A headless Claude session named by the caller rather than by Claude.
enum ClaudeSession: Equatable {
  case start(String)
  case resume(String)
}
