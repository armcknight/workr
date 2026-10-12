import Foundation

enum CleanCommand {
  static func run(branch: String, idleMinutes: Int?, dryRun: Bool = false, _ cfg: Config) throws {
    guard Git.inRepo() else {
      throw WorkError("Not in a git repository")
    }
    let mainCheckout = FileManager.default.currentDirectoryPath
    let worktree = absoluteWorktreePath(cfg.worktree.pathTemplate, branch: branch)
    let artifacts =
      BuildArtifacts.buildDirectories(worktree: worktree)
      + BuildArtifacts.derivedData(worktree: worktree, mainCheckout: mainCheckout)
    guard !artifacts.isEmpty else {
      print("No build output for \(branch)")
      return
    }
    if let idleMinutes, let last = BuildArtifacts.lastActivity(artifacts),
      Date().timeIntervalSince(last) < TimeInterval(idleMinutes * 60)
    {
      let minutes = Int(Date().timeIntervalSince(last) / 60)
      print("Kept the build output for \(branch): used \(minutes) minutes ago")
      return
    }
    if dryRun {
      list(artifacts)
      return
    }
    let freed = BuildArtifacts.remove(artifacts)
    print("Freed \(BuildArtifacts.formatBytes(freed)) for \(branch)")
  }

  /// Removes the DerivedData of worktrees that no longer exist: those whose
  /// recorded path lies under the worktree directory, or names one of this
  /// repository's branches' worktrees from before the repository moved, and
  /// those whose name hash matches a known branch's worktree path.
  static func runOrphans(dryRun: Bool = false, _ cfg: Config) throws {
    guard Git.inRepo() else {
      throw WorkError("Not in a git repository")
    }
    let fm = FileManager.default
    let mainCheckout = fm.currentDirectoryPath
    var orphans: [String] = []
    let branches = knownBranches()
    let recorded = BuildArtifacts.recordedWorkspaces().filter {
      !fm.fileExists(atPath: $0.workspace)
    }

    // A relative template such as worktrees/{branch} also identifies a
    // branch's worktree at the repository's old location.
    for (directory, workspace) in recorded
    where namesBranchWorktree(workspace, template: cfg.worktree.pathTemplate, branches: branches) {
      orphans.append(directory)
    }
    if let range = cfg.worktree.pathTemplate.range(of: "{branch}") {
      let root = absolutePath(String(cfg.worktree.pathTemplate[..<range.lowerBound]))
      for (directory, workspace) in recorded
      where workspace.hasPrefix(root) && !orphans.contains(directory) {
        orphans.append(directory)
      }
    }
    for branch in branches {
      let worktree = absoluteWorktreePath(cfg.worktree.pathTemplate, branch: branch)
      guard !fm.fileExists(atPath: worktree) else { continue }
      for directory in BuildArtifacts.derivedData(worktree: worktree, mainCheckout: mainCheckout)
      where !orphans.contains(directory) {
        orphans.append(directory)
      }
    }

    guard !orphans.isEmpty else {
      print("No DerivedData from removed worktrees")
      return
    }
    if dryRun {
      list(orphans)
      return
    }
    let freed = BuildArtifacts.remove(orphans)
    print("Freed \(BuildArtifacts.formatBytes(freed)) from removed worktrees")
  }

  private static func list(_ paths: [String]) {
    var total: Int64 = 0
    for path in paths {
      let bytes = BuildArtifacts.size(path)
      total += bytes
      print("Would remove \(path) (\(BuildArtifacts.formatBytes(bytes)))")
    }
    print("Would free \(BuildArtifacts.formatBytes(total))")
  }

  /// Whether `workspace` lies in one of `branches`' worktrees, wherever the
  /// repository was: for a relative template such as worktrees/{branch}, the
  /// path holds `/worktrees/<branch>` as whole components.
  static func namesBranchWorktree(_ workspace: String, template: String, branches: [String]) -> Bool
  {
    guard !template.hasPrefix("/") else { return false }
    return branches.contains { branch in
      let marker = "/" + template.replacingOccurrences(of: "{branch}", with: branch)
      return workspace.hasSuffix(marker) || workspace.contains(marker + "/")
    }
  }

  static func absoluteWorktreePath(_ template: String, branch: String) -> String {
    absolutePath(template.replacingOccurrences(of: "{branch}", with: branch))
  }

  static func absolutePath(_ path: String) -> String {
    let expanded = NSString(string: path).expandingTildeInPath
    let absolute =
      expanded.hasPrefix("/")
      ? expanded : "\(FileManager.default.currentDirectoryPath)/\(expanded)"
    // Keeps a trailing slash, which marks a directory prefix.
    let standardized = URL(fileURLWithPath: absolute).standardizedFileURL.path
    return path.hasSuffix("/") && !standardized.hasSuffix("/") ? standardized + "/" : standardized
  }

  /// Local branches, and remote ones without their remote's name.
  private static func knownBranches() -> [String] {
    let remotes = Set(
      ((try? Shell.capture("git", ["remote"]))?.stdoutString ?? "").split(separator: "\n").map(
        String.init))
    let output = try? Shell.capture(
      "git", ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"])
    let refs = (output?.stdoutString ?? "").split(separator: "\n").map(String.init)
    return Array(Set(refs.map { stripRemote($0, remotes: remotes) })).filter { $0 != "HEAD" }
      .sorted()
  }

  /// `origin/linear/x` → `linear/x`; a local `linear/x` stays as it is.
  static func stripRemote(_ ref: String, remotes: Set<String>) -> String {
    guard let slash = ref.firstIndex(of: "/"), remotes.contains(String(ref[..<slash])) else {
      return ref
    }
    return String(ref[ref.index(after: slash)...])
  }
}
