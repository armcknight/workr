import ArgumentParser

struct Term: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "term",
    abstract: "Open/attach the tmuxinator session for the current git branch."
  )

  func run() throws {
    let cfg = try Config.load()
    try TermCommand.run(cfg)
  }
}
