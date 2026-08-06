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
