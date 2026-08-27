import Foundation

/// Shared PR annotation used by both `work coder status` and `work boxdev
/// status`. Port of the helpers in src/cmd/status.rs.
enum PRAnnotation {
  /// Find a PR whose headRefName contains the workspace/box name and render
  /// `<url>  <state>, <checks>`; `-` when unmatched.
  static func annotate(_ workspaceName: String, _ prs: [JSON]) -> String {
    let match = prs.first { pr in
      (pr["headRefName"].string?.contains(workspaceName)) ?? false
    }
    guard let pr = match else { return "-" }

    let url = pr["url"].string ?? ""
    let stateLabel = prState(pr)
    let checks = pr["statusCheckRollup"].array ?? []
    let checksLabel = checksSummary(checks)
    return "\(url)  \(stateLabel), \(checksLabel)"
  }

  static func prState(_ pr: JSON) -> String {
    let state = pr["state"].string ?? ""
    if state == "MERGED" { return "merged" }
    if state == "CLOSED" { return "closed" }
    if pr["isDraft"].bool ?? false { return "draft" }
    switch pr["reviewDecision"].string ?? "" {
    case "APPROVED": return "approved"
    case "CHANGES_REQUESTED": return "changes requested"
    default: return "needs review"
    }
  }

  static func checksSummary(_ checks: [JSON]) -> String {
    if checks.isEmpty { return "no checks" }
    let states = checks.map(checkState)
    if states.contains("failing") { return "failing" }
    if states.contains("running") { return "running" }
    return "passing"
  }

  static func checkState(_ check: JSON) -> String {
    switch check["__typename"].string {
    case "CheckRun":
      let conclusion = check["conclusion"].string ?? ""
      switch conclusion {
      case "FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE":
        return "failing"
      default:
        let status = check["status"].string ?? ""
        return status == "COMPLETED" ? "passing" : "running"
      }
    case "StatusContext":
      switch check["state"].string ?? "" {
      case "FAILURE", "ERROR": return "failing"
      case "PENDING": return "running"
      default: return "passing"
      }
    default:
      return "?"
    }
  }
}
