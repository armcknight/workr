import Foundation

/// A slash-command markdown block inlined at the end of the bootstrap prompt.
struct RenderedSection {
  let heading: String
  let body: String
}

/// Port of src/prompt.rs.
enum Prompt {
  /// Load inline slash-command sections, tolerating missing files (matches
  /// the fish `test -f` guard). Throws only on a real read error.
  static func loadInlinedSections(_ cfg: PromptConfig, commandsDir: String) throws
    -> [RenderedSection]
  {
    var out: [RenderedSection] = []
    for section in cfg.inlineSections {
      let path = (commandsDir as NSString).appendingPathComponent(section.file)
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue
      else {
        continue
      }
      let body: String
      do {
        body = try String(contentsOfFile: path, encoding: .utf8)
      } catch {
        throw WorkError("reading \(path): \(error.localizedDescription)")
      }
      out.append(RenderedSection(heading: section.heading, body: body))
    }
    return out
  }

  /// Build the Claude bootstrap prompt from the Linear ticket payload.
  static func build(
    ticket: JSON, branch: String, workspacePaths: [String], sections: [RenderedSection]
  ) -> String {
    var s = ""
    let identifier = ticket["identifier"].string ?? "(unknown)"
    let title = ticket["title"].string ?? ""
    let url = ticket["url"].string ?? ""
    let state = ticket["state"]["name"].string ?? ""

    s += "# Linear ticket \(identifier): \(title)\n\n"
    s += "URL: \(url)\n"
    s += "State: \(state)\n\n"

    s += "## Description\n\n"
    let description = ticket["description"].string ?? ""
    s += description.isEmpty ? "(no description)" : description
    s += "\n\n## Comments\n\n"

    if let nodes = ticket["comments"]["nodes"].array, !nodes.isEmpty {
      let parts = nodes.map { c -> String in
        let user = c["user"]["name"].string ?? "comment"
        let date = String(
          (c["createdAt"].string ?? "").split(
            separator: "T", maxSplits: 1, omittingEmptySubsequences: false
          ).first ?? "")
        let body = c["body"].string ?? ""
        return "**\(user) (\(date)):**\n\(body)"
      }
      s += parts.joined(separator: "\n\n---\n\n")
    } else {
      s += "(no comments)"
    }

    s += "\n\n---\n\n## Working environment\n\n"
    s += formatWorkspacePaths(workspacePaths, branch: branch)
    s += "\n## Instructions\n\n"
    s +=
      "You are running autonomously inside a remote cloud dev environment — there is no human to confirm with mid-task, so do not stop to ask questions. Make reasonable judgement calls and proceed.\n\n"
      + "1. Read the ticket carefully.\n"
      + "2. Use TodoWrite to track the implementation steps as you work, so progress is visible.\n"
      + "3. Implement the changes.\n"
      + "4. Run tests and lints as appropriate.\n"
      + "5. Commit the changes (see Commit conventions below).\n"
      + "6. Open a draft pull request (see PR conventions below). Pass `--draft --autonomous` semantics: draft state, no browser.\n"

    for section in sections {
      s += "\n\n## \(section.heading)\n\n\(section.body)"
    }

    return s
  }

  private static func formatWorkspacePaths(_ paths: [String], branch: String) -> String {
    switch paths.count {
    case 0:
      return ""
    case 1:
      return "The repo you'll work in is at `\(paths[0])`, on branch `\(branch)`.\n"
    case 2:
      let parent = commonParent(paths)
      let tail = parent.isEmpty ? "" : " If it spans both, work from `\(parent)`."
      return
        "The repos you may need are at `\(paths[0])` and `\(paths[1])`, both on branch `\(branch)`.\n"
        + "Decide which repo(s) the task requires and `cd` accordingly.\(tail)\n"
    default:
      let formatted = paths.map { "`\($0)`" }.joined(separator: ", ")
      return "The repos you may need are at \(formatted), all on branch `\(branch)`.\n"
    }
  }

  static func commonParent(_ paths: [String]) -> String {
    if paths.isEmpty { return "" }
    let split = paths.map {
      $0.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }
    var common = split[0]
    for parts in split.dropFirst() {
      var next: [String] = []
      for (a, b) in zip(common, parts) {
        if a == b { next.append(a) } else { break }
      }
      common = next
    }
    // Only pop a trailing component when the common prefix exactly equals
    // every input — otherwise take_while already stopped at the divergence
    // point, which IS the shared parent.
    let allConsumed = split.allSatisfy { $0.count == common.count }
    if allConsumed && !common.isEmpty {
      common.removeLast()
    }
    return common.joined(separator: "/")
  }
}
