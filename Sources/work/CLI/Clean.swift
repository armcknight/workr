import ArgumentParser

struct Clean: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clean",
    abstract:
      "Remove a worktree's build output (SwiftPM .build, Xcode and XcodeBuildMCP DerivedData), keeping the worktree.",
    discussion: """
      Run from the repository's main checkout. Only generated build output is removed: \
      the worktree, its source and its ignored files such as .env stay.
      """
  )

  @Option(
    name: .long,
    help: "Leave the build output alone if it was used within this many minutes.")
  var idleMinutes: Int?

  @Flag(
    name: .long,
    help:
      "Instead of one branch, remove the DerivedData and XcodeBuildMCP data of this repository's worktrees that no longer exist."
  )
  var orphans = false

  @Flag(name: .long, help: "List what would be removed, with sizes, and remove nothing.")
  var dryRun = false

  @Argument(help: "Branch whose worktree to clean.")
  var branch: String?

  func validate() throws {
    if orphans == (branch != nil) {
      throw ValidationError("give either a branch or --orphans")
    }
    if orphans && idleMinutes != nil {
      throw ValidationError("--idle-minutes applies to a branch, not --orphans")
    }
  }

  func run() throws {
    let cfg = try Config.load()
    if orphans {
      try CleanCommand.runOrphans(dryRun: dryRun, cfg)
    } else if let branch {
      try CleanCommand.run(branch: branch, idleMinutes: idleMinutes, dryRun: dryRun, cfg)
    }
  }
}
