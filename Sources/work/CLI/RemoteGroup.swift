import ArgumentParser

struct RemoteGroup: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remote",
    abstract:
      "Cloud devbox operations via the configured provider plugin (status, log, prompt, test).",
    subcommands: [
      RemoteStatus.self,
      RemoteLog.self,
      RemotePrompt.self,
      RemoteTest.self,
    ]
  )
}

/// Shared `--provider <name>` option, defaulting to `[remote] provider`.
struct RemoteOption: ParsableArguments {
  @Option(
    name: [.short, .long], help: "Remote provider name (defaults to [remote] provider in config).")
  var provider: String?
}

struct RemoteStatus: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "List remote sessions from the provider, with PR annotation."
  )

  @OptionGroup var opts: RemoteOption

  func run() throws {
    try RemoteStatusCommand.run(Config.load(), provider: opts.provider ?? "")
  }
}

struct RemoteLog: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "log",
    abstract: "Stream / dump the provider's session transcript."
  )

  @OptionGroup var opts: RemoteOption

  @Argument(help: "Branch name or session slug.")
  var branch: String

  @Flag(name: [.short, .long], help: "Follow / stream until the session ends.")
  var follow = false

  func run() throws {
    try RemoteLogCommand.run(
      Config.load(), provider: opts.provider ?? "", branch: branch, follow: follow)
  }
}

struct RemotePrompt: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "prompt",
    abstract: "Send a follow-up prompt to a session's agent."
  )

  @OptionGroup var opts: RemoteOption

  @Argument(help: "Branch name or session slug.")
  var branch: String

  @Argument(parsing: .captureForPassthrough, help: "Prompt text (joined with spaces).")
  var text: [String] = []

  func validate() throws {
    if text.isEmpty {
      throw ValidationError("prompt text is required")
    }
  }

  func run() throws {
    try RemotePromptCommand.run(
      Config.load(), provider: opts.provider ?? "", branch: branch,
      text: text.joined(separator: " "))
  }
}

struct RemoteTest: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract: "Port-forward a session and open its devserver in a browser."
  )

  @OptionGroup var opts: RemoteOption

  @Argument(help: "Branch name or session slug.")
  var branch: String

  @Argument(help: "Port to forward (defaults to the provider's own default).")
  var port: Int?

  func run() throws {
    try RemoteTestCommand.run(
      Config.load(), provider: opts.provider ?? "", branch: branch, port: port)
  }
}
