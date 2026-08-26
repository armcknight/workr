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
            ticket: JSON(["identifier": "T", "title": "t", "url": "u", "state": ["name": "s"], "description": "", "comments": ["nodes": []]]),
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
        let s = Prompt.build(ticket: ticket, branch: "user/team-1-foo", workspacePaths: [], sections: [])
        XCTAssertTrue(s.hasPrefix("# Linear ticket TEAM-1: Do the thing"))
        XCTAssertTrue(s.contains("(no description)"))
        XCTAssertTrue(s.contains("(no comments)"))
        XCTAssertTrue(s.contains("## Instructions"))
    }
}

final class PRAnnotationTests: XCTestCase {
    func testPRStatePriority() {
        XCTAssertEqual(PRAnnotation.prState(JSON(["state": "MERGED", "isDraft": false, "reviewDecision": "APPROVED"])), "merged")
        XCTAssertEqual(PRAnnotation.prState(JSON(["state": "CLOSED", "isDraft": true])), "closed")
        XCTAssertEqual(PRAnnotation.prState(JSON(["state": "OPEN", "isDraft": true, "reviewDecision": ""])), "draft")
        XCTAssertEqual(PRAnnotation.prState(JSON(["state": "OPEN", "isDraft": false, "reviewDecision": "APPROVED"])), "approved")
        XCTAssertEqual(PRAnnotation.prState(JSON(["state": "OPEN", "isDraft": false, "reviewDecision": "CHANGES_REQUESTED"])), "changes requested")
        XCTAssertEqual(PRAnnotation.prState(JSON(["state": "OPEN", "isDraft": false, "reviewDecision": "REVIEW_REQUIRED"])), "needs review")
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
        let prs = [JSON([
            "url": "https://github.com/x/y/pull/1",
            "headRefName": "user/team-1-foo",
            "isDraft": true,
            "state": "OPEN",
            "reviewDecision": "",
            "statusCheckRollup": [],
        ])]
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
