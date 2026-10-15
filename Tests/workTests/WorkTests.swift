import XCTest

@testable import work

final class TmuxTests: XCTestCase {
  func testSlugifyPwdHandlesMacosPath() {
    XCTAssertEqual(
      Tmux.slugifyPwd("/Users/me/code/foo.bar/worktrees/x"),
      "users-me-code-foobar-worktrees-x"
    )
  }

  func testSlugifyBranchLowercasesAndReplacesSlashes() {
    XCTAssertEqual(
      Tmux.slugifyBranch("User/TEAM-1-foo"),
      "user-team-1-foo"
    )
  }
}

final class ExtractTicketTests: XCTestCase {
  func testLowercase() {
    XCTAssertEqual(StartCommand.extractTicketID("user/team-221-foo"), "TEAM-221")
  }
  func testNoPrefix() {
    XCTAssertEqual(StartCommand.extractTicketID("team-99-thing"), "TEAM-99")
  }
  func testFirstWhenMultiple() {
    XCTAssertEqual(StartCommand.extractTicketID("user/aa-1-bb-2-cc-3"), "AA-1")
  }
  func testNoneWhenAbsent() {
    XCTAssertNil(StartCommand.extractTicketID("user/plain-slug"))
  }
}

final class PromptTests: XCTestCase {
  func testCommonParent() {
    XCTAssertEqual(Prompt.commonParent(["/workspace/repo-a", "/workspace/repo-b"]), "/workspace")
  }

  func testTwoPathForm() {
    let s = Prompt.build(
      ticket: JSON([
        "identifier": "T", "title": "t", "url": "u", "state": ["name": "s"], "description": "",
        "comments": ["nodes": []],
      ]),
      branch: "user/team-1-foo",
      workspacePaths: ["/workspace/a", "/workspace/b"],
      sections: []
    )
    XCTAssertTrue(s.contains("`/workspace/a` and `/workspace/b`"))
    XCTAssertTrue(s.contains("on branch `user/team-1-foo`"))
    XCTAssertTrue(s.contains("work from `/workspace`"))
  }

  func testMinimalTicket() {
    let ticket = JSON([
      "identifier": "TEAM-1",
      "title": "Do the thing",
      "url": "https://example.com/TEAM-1",
      "state": ["name": "Todo"],
      "description": "",
      "comments": ["nodes": []],
    ])
    let s = Prompt.build(
      ticket: ticket, branch: "user/team-1-foo", workspacePaths: [], sections: [])
    XCTAssertTrue(s.hasPrefix("# Linear ticket TEAM-1: Do the thing"))
    XCTAssertTrue(s.contains("(no description)"))
    XCTAssertTrue(s.contains("(no comments)"))
    XCTAssertTrue(s.contains("## Instructions"))
  }
}

final class PRAnnotationTests: XCTestCase {
  func testPRStatePriority() {
    XCTAssertEqual(
      PRAnnotation.prState(
        JSON(["state": "MERGED", "isDraft": false, "reviewDecision": "APPROVED"])), "merged")
    XCTAssertEqual(PRAnnotation.prState(JSON(["state": "CLOSED", "isDraft": true])), "closed")
    XCTAssertEqual(
      PRAnnotation.prState(JSON(["state": "OPEN", "isDraft": true, "reviewDecision": ""])), "draft")
    XCTAssertEqual(
      PRAnnotation.prState(
        JSON(["state": "OPEN", "isDraft": false, "reviewDecision": "APPROVED"])), "approved")
    XCTAssertEqual(
      PRAnnotation.prState(
        JSON(["state": "OPEN", "isDraft": false, "reviewDecision": "CHANGES_REQUESTED"])),
      "changes requested")
    XCTAssertEqual(
      PRAnnotation.prState(
        JSON(["state": "OPEN", "isDraft": false, "reviewDecision": "REVIEW_REQUIRED"])),
      "needs review")
  }

  func testChecksSummaryRollups() {
    XCTAssertEqual(PRAnnotation.checksSummary([]), "no checks")
    let failing = JSON(["__typename": "CheckRun", "conclusion": "FAILURE", "status": "COMPLETED"])
    let passing = JSON(["__typename": "CheckRun", "conclusion": "SUCCESS", "status": "COMPLETED"])
    let running = JSON(["__typename": "CheckRun", "conclusion": NSNull(), "status": "IN_PROGRESS"])
    XCTAssertEqual(PRAnnotation.checksSummary([passing]), "passing")
    XCTAssertEqual(PRAnnotation.checksSummary([passing, running]), "running")
    XCTAssertEqual(PRAnnotation.checksSummary([passing, running, failing]), "failing")
  }

  func testAnnotateMatchesBySubstring() {
    let prs = [
      JSON([
        "url": "https://github.com/x/y/pull/1",
        "headRefName": "user/team-1-foo",
        "isDraft": true,
        "state": "OPEN",
        "reviewDecision": "",
        "statusCheckRollup": [],
      ])
    ]
    let s = PRAnnotation.annotate("team-1-foo", prs)
    XCTAssertTrue(s.contains("https://github.com/x/y/pull/1"))
    XCTAssertTrue(s.contains("draft"))
    XCTAssertTrue(s.contains("no checks"))
  }

  func testAnnotateUnmatchedReturnsDash() {
    XCTAssertEqual(PRAnnotation.annotate("nothing", []), "-")
  }
}

/// Branch resolution has to survive a detached HEAD, which is what git parks
/// you on mid-rebase. These drive real git repos in temp dirs because the
/// behavior under test *is* git's — `branch --show-current` going empty, and
/// the rebase state dir landing in a different place for a linked worktree
/// than for a plain clone.
final class GitSessionBranchTests: XCTestCase {
  private var originalCWD: String!
  private var tmp: String!

  override func setUp() {
    super.setUp()
    originalCWD = FileManager.default.currentDirectoryPath
    tmp = NSTemporaryDirectory() + "workr-git-tests-" + UUID().uuidString
    try? FileManager.default.createDirectory(
      atPath: tmp, withIntermediateDirectories: true)
  }

  override func tearDown() {
    // sessionBranch() reads the *process* working directory, so restore it
    // before the next test runs.
    FileManager.default.changeCurrentDirectoryPath(originalCWD)
    try? FileManager.default.removeItem(atPath: tmp)
    super.tearDown()
  }

  @discardableResult
  private func git(_ args: [String], in dir: String) -> CommandOutput? {
    // -c flags keep these repos independent of the developer's git identity.
    let identity = [
      "-c", "user.email=test@example.com",
      "-c", "user.name=Test",
      "-c", "commit.gpgsign=false",
    ]
    return try? Shell.capture("git", identity + args, currentDirectory: dir)
  }

  private func write(_ text: String, to path: String) {
    try? text.write(toFile: path, atomically: true, encoding: .utf8)
  }

  /// Build a repo whose `topic` branch conflicts with `main`, then start the
  /// rebase so it stops on the conflict. Using a real conflict avoids needing
  /// to drive an interactive editor. Returns the repo path.
  private func repoStoppedMidRebase() -> String {
    let repo = tmp + "/repo"
    try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
    git(["init", "-q", "-b", "main"], in: repo)
    write("a\n", to: repo + "/file.txt")
    git(["add", "."], in: repo)
    git(["commit", "-q", "-m", "base"], in: repo)

    git(["checkout", "-q", "-b", "topic"], in: repo)
    write("b\n", to: repo + "/file.txt")
    git(["commit", "-q", "-am", "topic change"], in: repo)

    git(["checkout", "-q", "main"], in: repo)
    write("c\n", to: repo + "/file.txt")
    git(["commit", "-q", "-am", "main change"], in: repo)

    git(["checkout", "-q", "topic"], in: repo)
    git(["rebase", "main"], in: repo)  // conflicts, leaving us mid-rebase
    return repo
  }

  func testResolvesBranchNormally() throws {
    let repo = tmp + "/plain"
    try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
    git(["init", "-q", "-b", "main"], in: repo)
    git(["commit", "-q", "--allow-empty", "-m", "one"], in: repo)

    FileManager.default.changeCurrentDirectoryPath(repo)
    XCTAssertEqual(try Git.sessionBranch(), "main")
  }

  func testResolvesBranchMidRebaseInPlainRepo() throws {
    let repo = repoStoppedMidRebase()
    FileManager.default.changeCurrentDirectoryPath(repo)

    // Precondition: this is the state that used to be misreported as
    // "not in a git repository".
    XCTAssertTrue(Git.inRepo())
    XCTAssertEqual(try Git.currentBranch(), "", "expected detached HEAD mid-rebase")

    XCTAssertEqual(try Git.sessionBranch(), "topic")
  }

  func testResolvesBranchMidRebaseInLinkedWorktree() throws {
    // In a linked worktree `.git` is a file and the rebase state lives under
    // the main repo's .git/worktrees/<name>/, so a naive ".git/rebase-merge"
    // lookup would miss it.
    let repo = tmp + "/wt-main"
    try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
    git(["init", "-q", "-b", "main"], in: repo)
    write("a\n", to: repo + "/file.txt")
    git(["add", "."], in: repo)
    git(["commit", "-q", "-m", "base"], in: repo)

    let wt = tmp + "/wt-linked"
    git(["worktree", "add", "-q", wt, "-b", "sidebranch"], in: repo)

    write("b\n", to: wt + "/file.txt")
    git(["commit", "-q", "-am", "worktree change"], in: wt)

    write("c\n", to: repo + "/file.txt")
    git(["commit", "-q", "-am", "main change"], in: repo)

    git(["rebase", "main"], in: wt)  // conflicts

    FileManager.default.changeCurrentDirectoryPath(wt)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: wt + "/.git"),
      "expected .git to exist as a file in a linked worktree")
    XCTAssertEqual(try Git.currentBranch(), "", "expected detached HEAD mid-rebase")

    XCTAssertEqual(try Git.sessionBranch(), "sidebranch")
  }

  func testFallsBackToShortShaWhenDetachedWithoutRebase() throws {
    let repo = tmp + "/detached"
    try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
    git(["init", "-q", "-b", "main"], in: repo)
    git(["commit", "-q", "--allow-empty", "-m", "one"], in: repo)
    git(["checkout", "-q", "--detach", "HEAD"], in: repo)

    FileManager.default.changeCurrentDirectoryPath(repo)
    XCTAssertEqual(try Git.currentBranch(), "")
    XCTAssertNil(Git.rebaseHeadName(), "no rebase is running")

    let resolved = try Git.sessionBranch()
    XCTAssertTrue(
      resolved.hasPrefix("detached-"),
      "expected a detached-<sha> fallback, got \(resolved)")
  }
}

/// The other operations that could plausibly confuse branch resolution.
/// Merge/cherry-pick/revert keep you on your branch, so they need no handling
/// — these tests pin that down so a future refactor doesn't add speculative
/// support for them. Bisect *does* detach, and unlike a one-off detach its
/// HEAD moves at every step, so it needs the BISECT_START fallback.
final class GitOtherStateTests: XCTestCase {
  private var originalCWD: String!
  private var tmp: String!

  override func setUp() {
    super.setUp()
    originalCWD = FileManager.default.currentDirectoryPath
    tmp = NSTemporaryDirectory() + "workr-git-state-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
  }

  override func tearDown() {
    FileManager.default.changeCurrentDirectoryPath(originalCWD)
    try? FileManager.default.removeItem(atPath: tmp)
    super.tearDown()
  }

  @discardableResult
  private func git(_ args: [String], in dir: String) -> CommandOutput? {
    let identity = [
      "-c", "user.email=test@example.com",
      "-c", "user.name=Test",
      "-c", "commit.gpgsign=false",
    ]
    return try? Shell.capture("git", identity + args, currentDirectory: dir)
  }

  private func write(_ text: String, to path: String) {
    try? text.write(toFile: path, atomically: true, encoding: .utf8)
  }

  /// main and topic both edit the same line, so combining them conflicts.
  private func conflictingRepo() -> String {
    let repo = tmp + "/repo"
    try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
    git(["init", "-q", "-b", "main"], in: repo)
    write("a\n", to: repo + "/file.txt")
    git(["add", "."], in: repo)
    git(["commit", "-q", "-m", "base"], in: repo)

    git(["checkout", "-q", "-b", "topic"], in: repo)
    write("b\n", to: repo + "/file.txt")
    git(["commit", "-q", "-am", "topic change"], in: repo)

    git(["checkout", "-q", "main"], in: repo)
    write("c\n", to: repo + "/file.txt")
    git(["commit", "-q", "-am", "main change"], in: repo)
    return repo
  }

  func testMergeConflictStaysOnBranch() throws {
    let repo = conflictingRepo()
    git(["merge", "topic"], in: repo)  // conflicts
    FileManager.default.changeCurrentDirectoryPath(repo)

    XCTAssertEqual(try Git.currentBranch(), "main", "merge should not detach HEAD")
    XCTAssertEqual(try Git.sessionBranch(), "main")
  }

  func testCherryPickConflictStaysOnBranch() throws {
    let repo = conflictingRepo()
    git(["cherry-pick", "topic"], in: repo)  // conflicts
    FileManager.default.changeCurrentDirectoryPath(repo)

    XCTAssertEqual(try Git.currentBranch(), "main", "cherry-pick should not detach HEAD")
    XCTAssertEqual(try Git.sessionBranch(), "main")
  }

  func testBisectResolvesToStartingBranch() throws {
    let repo = tmp + "/bisect"
    try? FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
    git(["init", "-q", "-b", "main"], in: repo)
    for n in ["one", "two", "three", "four"] {
      git(["commit", "-q", "--allow-empty", "-m", n], in: repo)
    }
    git(["bisect", "start"], in: repo)
    git(["bisect", "bad"], in: repo)
    git(["bisect", "good", "HEAD~3"], in: repo)

    FileManager.default.changeCurrentDirectoryPath(repo)
    XCTAssertEqual(try Git.currentBranch(), "", "bisect is expected to detach HEAD")
    XCTAssertNil(Git.rebaseHeadName(), "no rebase is running")

    // Must be the branch, not a SHA: HEAD moves each bisect step, so a
    // SHA-derived name would open a new tmux session per step.
    XCTAssertEqual(try Git.sessionBranch(), "main")

    git(["bisect", "reset"], in: repo)
  }
}

final class HeadlessSessionTests: XCTestCase {
  func testNoSessionLeavesClaudeToPickOne() {
    XCTAssertEqual(
      StartCommand.claudeHeadlessArguments(session: nil),
      ["claude", "-p", "--dangerously-skip-permissions"])
  }

  func testStartNamesTheSession() {
    XCTAssertEqual(
      StartCommand.claudeHeadlessArguments(session: .start("abc")),
      ["claude", "-p", "--dangerously-skip-permissions", "--session-id", "abc"])
  }

  func testResumeContinuesTheSession() {
    XCTAssertEqual(
      StartCommand.claudeHeadlessArguments(session: .resume("abc")),
      ["claude", "-p", "--dangerously-skip-permissions", "--resume", "abc"])
  }

  func testParsesSessionId() throws {
    let start = try Start.parse([
      "--headless", "--prompt-file", "p", "--session-id", "abc", "branch",
    ])
    XCTAssertEqual(start.claudeSession, .start("abc"))
  }

  func testParsesResume() throws {
    let start = try Start.parse(["--headless", "--prompt-file", "p", "--resume", "abc", "branch"])
    XCTAssertEqual(start.claudeSession, .resume("abc"))
  }

  func testRejectsBothSessionFlags() {
    XCTAssertThrowsError(
      try Start.parse([
        "--headless", "--prompt-file", "p", "--session-id", "a", "--resume", "b", "branch",
      ]))
  }

  func testRejectsSessionOutsideHeadless() {
    XCTAssertThrowsError(try Start.parse(["--session-id", "a", "branch"]))
    XCTAssertThrowsError(try Start.parse(["--headless", "--session-id", "a", "branch"]))
  }
}

final class BuildArtifactsTests: XCTestCase {
  private var root: String!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(atPath: root)
  }

  private func mkdir(_ path: String) throws {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
  }

  private func writeInfo(_ directory: String, workspace: String) throws {
    let data = try PropertyListSerialization.data(
      fromPropertyList: [
        "WorkspacePath": workspace, "LastAccessedDate": Date(timeIntervalSince1970: 1),
      ],
      format: .xml, options: 0)
    FileManager.default.createFile(atPath: "\(directory)/info.plist", contents: data)
  }

  // The expected value comes from the same algorithm checked against every
  // DerivedData directory on a machine that recorded its workspace path.
  func testDerivedDataHashMatchesXcode() {
    XCTAssertEqual(
      BuildArtifacts.derivedDataHash("/Users/me/repo/worktrees/linear/a-1-x/App.xcodeproj"),
      "akscccjmyzycbpenlanlbuxktmxw")
  }

  func testFindsDerivedDataByHashAndByRecordedPath() throws {
    let derived = "\(root!)/DerivedData"
    let main = "\(root!)/repo"
    let worktree = "\(main)/worktrees/linear/a-1"
    try mkdir("\(worktree)/App.xcodeproj")
    let byHash = "\(derived)/App-\(BuildArtifacts.derivedDataHash("\(worktree)/App.xcodeproj"))"
    let byRecord = "\(derived)/Other-zzzz"
    let unrelated = "\(derived)/App-aaaa"
    for directory in [byHash, byRecord, unrelated] { try mkdir(directory) }
    try writeInfo(byRecord, workspace: "\(worktree)/Package.swift")
    try writeInfo(unrelated, workspace: "\(main)/App.xcodeproj")

    let found = BuildArtifacts.derivedData(worktree: worktree, mainCheckout: main, root: derived)
    XCTAssertEqual(Set(found), [byHash, byRecord])
  }

  func testFindsDerivedDataOfARemovedWorktreeFromTheMainCheckoutsProjects() throws {
    let derived = "\(root!)/DerivedData"
    let main = "\(root!)/repo"
    let worktree = "\(main)/worktrees/linear/gone"
    try mkdir("\(main)/App.xcodeproj")
    let orphan = "\(derived)/App-\(BuildArtifacts.derivedDataHash("\(worktree)/App.xcodeproj"))"
    try mkdir(orphan)

    XCTAssertEqual(
      BuildArtifacts.derivedData(worktree: worktree, mainCheckout: main, root: derived), [orphan])
  }

  // The same algorithm matched XcodeBuildMCP's directory for a real worktree.
  func testXcodeBuildMCPKeyMatchesXcodeBuildMCP() {
    XCTAssertEqual(
      BuildArtifacts.xcodeBuildMCPKey("/Users/me/repo/worktrees/linear/a-1-x"),
      "a-1-x-83fd1ccb0741")
    XCTAssertTrue(BuildArtifacts.xcodeBuildMCPKey("/a/.My App!.").hasPrefix("My-App-"))
    XCTAssertTrue(BuildArtifacts.xcodeBuildMCPKey("/").hasPrefix("workspace-"))
  }

  func testFindsXcodeBuildMCPWorkspaceByRealPath() throws {
    let workspaces = "\(root!)/workspaces"
    let worktree = "\(root!)/repo/worktrees/linear/a-1"
    try mkdir(worktree)
    let link = "\(root!)/link"
    try FileManager.default.createSymbolicLink(
      atPath: link, withDestinationPath: "\(root!)/repo")
    let real = realpath(worktree, nil).map { pointer in
      defer { free(pointer) }
      return String(cString: pointer)
    }!
    let directory = "\(workspaces)/\(BuildArtifacts.xcodeBuildMCPKey(real))"
    try mkdir("\(directory)/DerivedData")
    try mkdir("\(directory)/logs")

    XCTAssertEqual(
      BuildArtifacts.xcodeBuildMCPWorkspace(
        worktree: "\(link)/worktrees/linear/a-1", root: workspaces), directory)
    XCTAssertEqual(
      CleanCommand.xcodeBuildMCPDerivedData(worktree: worktree, root: workspaces),
      ["\(directory)/DerivedData"])
    XCTAssertNil(
      BuildArtifacts.xcodeBuildMCPWorkspace(
        worktree: "\(root!)/repo/worktrees/linear/a-2", root: workspaces))
  }

  func testFindsBuildDirectoriesAtTheRootAndOneLevelDown() throws {
    let worktree = "\(root!)/wt"
    for path in [
      "\(worktree)/.build", "\(worktree)/Package/.build", "\(worktree)/a/b/.build",
      "\(worktree)/.hidden/.build",
    ] {
      try mkdir(path)
    }
    XCTAssertEqual(
      BuildArtifacts.buildDirectories(worktree: worktree),
      ["\(worktree)/.build", "\(worktree)/Package/.build"])
  }

  func testLastActivityReadsBuildsAndXcodesAccessDate() throws {
    let build = "\(root!)/wt/.build/arm64/debug"
    try mkdir(build)
    let old = Date(timeIntervalSince1970: 1_000)
    for path in ["\(root!)/wt/.build", "\(root!)/wt/.build/arm64"] {
      try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)
    }
    let newer = Date(timeIntervalSince1970: 5_000)
    try FileManager.default.setAttributes([.modificationDate: newer], ofItemAtPath: build)
    XCTAssertEqual(BuildArtifacts.lastActivity(["\(root!)/wt/.build"]), newer)
  }

  func testRemoveFreesAndReportsBytes() throws {
    let directory = "\(root!)/wt/.build"
    try mkdir(directory)
    FileManager.default.createFile(
      atPath: "\(directory)/f", contents: Data(repeating: 1, count: 10_000))
    XCTAssertGreaterThan(BuildArtifacts.remove([directory]), 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory))
  }
}

final class CleanCommandTests: XCTestCase {
  func testNeedsABranchOrOrphans() {
    XCTAssertNoThrow(try Clean.parse(["linear/a-1"]))
    XCTAssertNoThrow(try Clean.parse(["linear/a-1", "--idle-minutes", "60"]))
    XCTAssertNoThrow(try Clean.parse(["--orphans"]))
    XCTAssertThrowsError(try Clean.parse([]))
    XCTAssertThrowsError(try Clean.parse(["linear/a-1", "--orphans"]))
    XCTAssertThrowsError(try Clean.parse(["--orphans", "--idle-minutes", "5"]))
  }

  func testRecognisesABranchWorktreeFromBeforeTheRepositoryMoved() {
    let branches = ["linear/cla-23-remove-hangs", "linear/cla-2"]
    let template = "worktrees/{branch}"
    XCTAssertTrue(
      CleanCommand.namesBranchWorktree(
        "/old/claude-squad/worktrees/linear/cla-23-remove-hangs/App.xcodeproj", template: template,
        branches: branches))
    // Whole components only: cla-2 is not cla-23.
    XCTAssertFalse(
      CleanCommand.namesBranchWorktree(
        "/old/claude-squad/worktrees/linear/cla-23/App.xcodeproj", template: template,
        branches: ["linear/cla-2"]))
    XCTAssertFalse(
      CleanCommand.namesBranchWorktree(
        "/elsewhere/App.xcodeproj", template: template, branches: branches))
    XCTAssertFalse(
      CleanCommand.namesBranchWorktree(
        "/old/worktrees/linear/cla-2/App.xcodeproj", template: "/abs/{branch}", branches: branches))
  }

  func testStripsOnlyKnownRemotes() {
    XCTAssertEqual(CleanCommand.stripRemote("origin/linear/a-1", remotes: ["origin"]), "linear/a-1")
    XCTAssertEqual(CleanCommand.stripRemote("linear/a-1", remotes: ["origin"]), "linear/a-1")
  }

  func testAbsolutePathsKeepATrailingSlash() {
    XCTAssertEqual(CleanCommand.absolutePath("/repo/worktrees/"), "/repo/worktrees/")
    XCTAssertEqual(CleanCommand.absolutePath("/repo/./worktrees/x"), "/repo/worktrees/x")
  }
}

final class SubmoduleWorktreeRemovalTests: XCTestCase {
  private var root: String!
  private var worktree: String { "\(root!)/repo/worktrees/b" }
  private var submodule: String { "\(worktree)/lib" }

  private func git(_ path: String, _ arguments: String...) throws {
    let output = try Shell.capture(
      "git",
      ["-C", path, "-c", "user.name=t", "-c", "user.email=t@t", "-c", "protocol.file.allow=always"]
        + arguments)
    XCTAssertTrue(output.succeeded, "git \(arguments): \(output.stderrString)")
  }

  private func write(_ path: String, _ text: String = "x\n") {
    FileManager.default.createFile(atPath: path, contents: Data(text.utf8))
  }

  /// A repository with a submodule whose own repository is its remote, and a
  /// worktree on branch `b` with the submodule checked out.
  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    for directory in ["lib", "repo"] {
      try FileManager.default.createDirectory(atPath: "\(root!)/\(directory)", withIntermediateDirectories: true)
      try git("\(root!)/\(directory)", "init", "-q", "-b", "main")
      write("\(root!)/\(directory)/README")
      try git("\(root!)/\(directory)", "add", "README")
      try git("\(root!)/\(directory)", "commit", "-q", "-m", "init")
    }
    try git("\(root!)/repo", "submodule", "add", "-q", "\(root!)/lib", "lib")
    try git("\(root!)/repo", "commit", "-q", "-m", "add lib")
    try git("\(root!)/repo", "worktree", "add", "-q", "-b", "b", "worktrees/b")
    try git(worktree, "submodule", "update", "-q", "--init")
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(atPath: root)
  }

  func testFindsCheckedOutSubmodules() {
    XCTAssertEqual(Submodules.checkedOut(in: worktree).map { URL(fileURLWithPath: $0).lastPathComponent }, ["lib"])
  }

  func testCleanSubmoduleIsRemovedByForce() throws {
    XCTAssertEqual(Submodules.unsavedWork(in: worktree), [])
    // `work finish` runs in the main checkout.
    let previous = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath("\(root!)/repo")
    defer { FileManager.default.changeCurrentDirectoryPath(previous) }
    try Git.worktreeRemove(worktree)
    XCTAssertFalse(FileManager.default.fileExists(atPath: worktree))
  }

  func testUncommittedChangeInSubmoduleBlocksRemoval() throws {
    write("\(submodule)/README", "changed\n")
    XCTAssertThrowsError(try Git.worktreeRemove(worktree))
    XCTAssertTrue(FileManager.default.fileExists(atPath: "\(submodule)/README"))
  }

  func testUntrackedFileInSubmoduleBlocksRemoval() {
    write("\(submodule)/new")
    XCTAssertEqual(Submodules.unsavedWork(in: worktree).count, 1)
  }

  // Committed in the submodule but pushed nowhere: lost with its git directory.
  func testUnpushedCommitInSubmoduleBlocksRemoval() throws {
    write("\(submodule)/new")
    try git(submodule, "add", "new")
    try git(submodule, "commit", "-q", "-m", "local only")
    XCTAssertTrue(Submodules.unsavedWork(in: worktree).contains { $0.contains("1 commit(s) on no remote branch") })
    XCTAssertThrowsError(try Git.worktreeRemove(worktree))
  }

  // Once the remote has it, as after a push, the commit is safe.
  func testCommitTheRemoteHasDoesNotBlock() throws {
    write("\(root!)/lib/later")
    try git("\(root!)/lib", "add", "later")
    try git("\(root!)/lib", "commit", "-q", "-m", "upstream")
    try git(submodule, "pull", "-q", "origin", "main")
    // The pointer change is the worktree's own uncommitted change; commit it.
    try git(worktree, "commit", "-q", "-am", "bump lib")
    XCTAssertEqual(Submodules.unsavedWork(in: worktree), [])
  }

  func testStashInSubmoduleBlocksRemoval() throws {
    write("\(submodule)/README", "changed\n")
    try git(submodule, "stash", "-q")
    XCTAssertEqual(Submodules.unsavedWork(in: worktree).map { $0.hasSuffix("1 stash(es)") }, [true])
  }

  func testUncommittedSubmodulePointerBlocksRemoval() throws {
    write("\(submodule)/new")
    try git(submodule, "add", "new")
    try git(submodule, "commit", "-q", "-m", "local only")
    XCTAssertTrue(Submodules.unsavedWork(in: worktree).contains { $0.hasPrefix(self.worktree + ":") })
  }

  func testUntrackedFileInWorktreeBlocksRemoval() {
    write("\(worktree)/notes")
    XCTAssertEqual(Submodules.unsavedWork(in: worktree).count, 1)
  }
}
