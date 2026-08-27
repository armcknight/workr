import Foundation

/// GitHub operations that stay in core (provider-agnostic). Branch seeding
/// moved to the provider plugin that needs it.
enum GitHub {
  /// `gh pr list --repo R --author @me --state all --json <fields> --limit 100`.
  /// Returns empty on failure but warns to stderr so a transient failure isn't
  /// mistaken for "no PRs".
  static func listUserPRs(repo: String, fields: [String]) -> [JSON] {
    if fields.isEmpty { return [] }
    let fieldsCSV = fields.joined(separator: ",")
    let out: CommandOutput
    do {
      out = try Shell.capture(
        "gh",
        [
          "pr", "list",
          "--repo", repo,
          "--author", "@me",
          "--state", "all",
          "--json", fieldsCSV,
          "--limit", "100",
        ])
    } catch {
      ewrite("warning: could not run `gh pr list` for \(repo): \(error)")
      return []
    }
    if !out.succeeded {
      ewrite("warning: `gh pr list` for \(repo) failed: \(out.stderrString.trimmed)")
      return []
    }
    guard let prs = JSON.parse(out.stdout)?.array else {
      ewrite("warning: could not parse `gh pr list` output for \(repo)")
      return []
    }
    return prs
  }
}
