import Foundation

/// Whether a worktree with submodules can be removed without losing work.
///
/// git refuses to remove a worktree that has submodules unless forced. Forcing
/// deletes each submodule's git directory, which lives under the worktree's
/// own admin directory (`.git/worktrees/<name>/modules/`), so its uncommitted
/// changes, local branches and stashes go too, as do any changes in the
/// worktree itself. `unsavedWork(in:)` finds all of these first.
enum Submodules {
  /// The worktree's checked-out submodules, nested ones included, as absolute
  /// paths. Submodules never initialized have nothing to lose.
  static func checkedOut(in worktree: String) -> [String] {
    guard
      let output = git(
        worktree, "submodule", "foreach", "--quiet", "--recursive", "echo \"$toplevel/$sm_path\"")
    else { return [] }
    return output.split(separator: "\n").map(String.init)
  }

  /// What forcing the worktree's removal would lose, one line each, or an
  /// empty list when nothing. Anything it cannot check counts as a loss.
  static func unsavedWork(in worktree: String) -> [String] {
    // In the worktree, a submodule moved to another commit without committing
    // that counts; changes inside a submodule are checked in the submodule.
    var problems = changes(in: worktree, ignoring: "dirty")
    for submodule in checkedOut(in: worktree) {
      problems += changes(in: submodule, ignoring: "dirty")
      problems += stashes(in: submodule)
      problems += commitsOnNoRemote(in: submodule)
    }
    return problems
  }

  private static func changes(in path: String, ignoring submodules: String) -> [String] {
    guard let status = git(path, "status", "--porcelain", "--ignore-submodules=\(submodules)") else {
      return ["\(path): could not read its status"]
    }
    let count = status.split(separator: "\n").count
    return count == 0 ? [] : ["\(path): \(count) uncommitted or untracked change(s)"]
  }

  private static func stashes(in path: String) -> [String] {
    guard let list = git(path, "stash", "list") else { return ["\(path): could not list its stashes"] }
    let count = list.split(separator: "\n").count
    return count == 0 ? [] : ["\(path): \(count) stash(es)"]
  }

  /// Commits on the submodule's HEAD or local branches that no remote branch
  /// has. The remote branches are fetched only when some commit is missing
  /// from them, as they usually have them all.
  private static func commitsOnNoRemote(in path: String) -> [String] {
    func count() -> Int? {
      git(path, "rev-list", "--count", "HEAD", "--branches", "--not", "--remotes").flatMap { Int($0) }
    }
    guard var missing = count() else { return ["\(path): could not compare its commits with its remotes"] }
    if missing > 0, git(path, "fetch", "--all", "--quiet") != nil {
      missing = count() ?? missing
    }
    return missing == 0 ? [] : ["\(path): \(missing) commit(s) on no remote branch"]
  }

  /// git's trimmed output, or nil when it fails.
  private static func git(_ path: String, _ arguments: String...) -> String? {
    guard let output = try? Shell.capture("git", ["-C", path] + arguments), output.succeeded else {
      return nil
    }
    return output.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
