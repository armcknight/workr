import Foundation
import TOMLKit

// Port of src/config.rs. Each struct mirrors a `#[serde(default,
// deny_unknown_fields)]` Rust struct: a default-seeded `init(from:)` gives
// serde's "missing key -> default" behavior, and `Decoding.rejectUnknownKeys`
// reproduces `deny_unknown_fields`.

/// Dynamic coding key used to enumerate the keys actually present in a table
/// so unknown ones can be rejected.
private struct AnyCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int? { nil }
  init(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}

/// User home directory. Prefers `$HOME` (matching Rust's `directories` crate,
/// which resolves the home dir from `$HOME` on Unix) and falls back to the
/// account's home if unset.
func homeDirectory() -> URL {
  if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
    return URL(fileURLWithPath: home)
  }
  return FileManager.default.homeDirectoryForCurrentUser
}

private enum Decoding {
  /// Throw if the decoded table has any key outside `known`, mirroring
  /// serde's `deny_unknown_fields`.
  static func rejectUnknownKeys(_ decoder: Decoder, known: Set<String>, table: String) throws {
    let dynamic = try decoder.container(keyedBy: AnyCodingKey.self)
    for key in dynamic.allKeys where !known.contains(key.stringValue) {
      throw WorkError("unknown field `\(key.stringValue)` in [\(table)]")
    }
  }
}

struct Config: Decodable {
  var worktree = WorktreeConfig()
  var tmux = TmuxConfig()
  var linear = LinearConfig()
  var remote = RemoteConfig()
  var project = ProjectConfig()
  var prompt = PromptConfig()
  var github = GithubConfig()

  enum CodingKeys: String, CodingKey {
    case worktree, tmux, linear, remote, project, prompt, github
  }

  init() {}

  init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try Decoding.rejectUnknownKeys(
      decoder, known: Set(CodingKeys.allCases.map(\.stringValue)), table: "")
    if let v = try c.decodeIfPresent(WorktreeConfig.self, forKey: .worktree) { worktree = v }
    if let v = try c.decodeIfPresent(TmuxConfig.self, forKey: .tmux) { tmux = v }
    if let v = try c.decodeIfPresent(LinearConfig.self, forKey: .linear) { linear = v }
    if let v = try c.decodeIfPresent(RemoteConfig.self, forKey: .remote) { remote = v }
    if let v = try c.decodeIfPresent(ProjectConfig.self, forKey: .project) { project = v }
    if let v = try c.decodeIfPresent(PromptConfig.self, forKey: .prompt) { prompt = v }
    if let v = try c.decodeIfPresent(GithubConfig.self, forKey: .github) { github = v }
  }

  /// Path to `~/.config/work/config.toml`.
  static func path() -> URL {
    homeDirectory().appendingPathComponent(".config/work/config.toml")
  }

  /// Load config from disk, falling back to all-defaults if the file is
  /// absent. Mirrors `Config::load`.
  static func load() throws -> Config {
    let path = path()
    guard FileManager.default.fileExists(atPath: path.path) else {
      return Config()
    }
    let text: String
    do {
      text = try String(contentsOf: path, encoding: .utf8)
    } catch {
      throw WorkError("reading config at \(path.path): \(error.localizedDescription)")
    }
    do {
      return try TOMLDecoder().decode(Config.self, from: text)
    } catch let e as WorkError {
      throw WorkError("parsing config at \(path.path): \(e.message)")
    } catch {
      throw WorkError("parsing config at \(path.path): \(error)")
    }
  }
}

extension Config.CodingKeys: CaseIterable {}

struct WorktreeConfig: Decodable {
  var pathTemplate: String
  var symlinkFiles: [String]
  var postCreateCommand: String

  enum CodingKeys: String, CodingKey, CaseIterable {
    case pathTemplate = "path_template"
    case symlinkFiles = "symlink_files"
    case postCreateCommand = "post_create_command"
  }

  init() {
    pathTemplate = "worktrees/{branch}"
    symlinkFiles = [".env", ".envrc", "fastlane/.env"]
    postCreateCommand = "make init"
  }

  init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try Decoding.rejectUnknownKeys(
      decoder, known: Set(CodingKeys.allCases.map(\.stringValue)), table: "worktree")
    if let v = try c.decodeIfPresent(String.self, forKey: .pathTemplate) { pathTemplate = v }
    if let v = try c.decodeIfPresent([String].self, forKey: .symlinkFiles) { symlinkFiles = v }
    if let v = try c.decodeIfPresent(String.self, forKey: .postCreateCommand) {
      postCreateCommand = v
    }
  }
}

struct TmuxConfig: Decodable {
  var tmuxinatorConfig: String

  enum CodingKeys: String, CodingKey, CaseIterable {
    case tmuxinatorConfig = "tmuxinator_config"
  }

  init() { tmuxinatorConfig = "dev" }

  init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try Decoding.rejectUnknownKeys(
      decoder, known: Set(CodingKeys.allCases.map(\.stringValue)), table: "tmux")
    if let v = try c.decodeIfPresent(String.self, forKey: .tmuxinatorConfig) {
      tmuxinatorConfig = v
    }
  }
}

struct LinearConfig: Decodable {
  var autoUpdateState: Bool
  var stateName: String

  enum CodingKeys: String, CodingKey, CaseIterable {
    case autoUpdateState = "auto_update_state"
    case stateName = "state_name"
  }

  init() {
    autoUpdateState = true
    stateName = "In Progress"
  }

  init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try Decoding.rejectUnknownKeys(
      decoder, known: Set(CodingKeys.allCases.map(\.stringValue)), table: "linear")
    if let v = try c.decodeIfPresent(Bool.self, forKey: .autoUpdateState) { autoUpdateState = v }
    if let v = try c.decodeIfPresent(String.self, forKey: .stateName) { stateName = v }
  }
}

/// Remote-provider selection. Provider mechanics live in an out-of-tree
/// plugin executable `work-remote-<provider>` (found on PATH, or at `path`).
struct RemoteConfig: Decodable {
  /// Default provider name for `work remote <op>` (and `--remote` when the
  /// value is omitted). Empty means no default configured.
  var provider: String
  /// Explicit path to the plugin executable, overriding PATH lookup. Empty
  /// means resolve `work-remote-<provider>` on PATH.
  var path: String

  enum CodingKeys: String, CodingKey, CaseIterable {
    case provider, path
  }

  init() {
    provider = ""
    path = ""
  }

  init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try Decoding.rejectUnknownKeys(
      decoder, known: Set(CodingKeys.allCases.map(\.stringValue)), table: "remote")
    if let v = try c.decodeIfPresent(String.self, forKey: .provider) { provider = v }
    if let v = try c.decodeIfPresent(String.self, forKey: .path) { path = v }
  }
}

/// Project-level (provider-agnostic) settings. `repos` is the set of repos
/// your work spans — used by core's PR annotation and forwarded to providers
/// that pre-seed branches.
struct ProjectConfig: Decodable {
  var repos: [String]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case repos
  }

  init() { repos = [] }

  init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try Decoding.rejectUnknownKeys(
      decoder, known: Set(CodingKeys.allCases.map(\.stringValue)), table: "project")
    if let v = try c.decodeIfPresent([String].self, forKey: .repos) { repos = v }
  }
}

struct PromptConfig: Decodable {
  var slashCommandsDir: String
  var inlineSections: [InlineSection]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case slashCommandsDir = "slash_commands_dir"
    case inlineSections = "inline_sections"
  }

  init() {
    slashCommandsDir = "~/.claude/commands"
    inlineSections = []
  }

  init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try Decoding.rejectUnknownKeys(
      decoder, known: Set(CodingKeys.allCases.map(\.stringValue)), table: "prompt")
    if let v = try c.decodeIfPresent(String.self, forKey: .slashCommandsDir) {
      slashCommandsDir = v
    }
    if let v = try c.decodeIfPresent([InlineSection].self, forKey: .inlineSections) {
      inlineSections = v
    }
  }
}

struct InlineSection: Decodable {
  var file: String
  var heading: String

  enum CodingKeys: String, CodingKey, CaseIterable {
    case file, heading
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try Decoding.rejectUnknownKeys(
      decoder, known: Set(CodingKeys.allCases.map(\.stringValue)), table: "prompt.inline_sections")
    file = try c.decode(String.self, forKey: .file)
    heading = try c.decode(String.self, forKey: .heading)
  }
}

struct GithubConfig: Decodable {
  var prFields: [String]

  enum CodingKeys: String, CodingKey, CaseIterable {
    case prFields = "pr_fields"
  }

  init() {
    prFields = ["url", "headRefName", "isDraft", "state", "reviewDecision", "statusCheckRollup"]
  }

  init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try Decoding.rejectUnknownKeys(
      decoder, known: Set(CodingKeys.allCases.map(\.stringValue)), table: "github")
    if let v = try c.decodeIfPresent([String].self, forKey: .prFields) { prFields = v }
  }
}

/// Expand a leading `~/` in a path string to the user's home directory.
/// Mirrors `config::expand_tilde`.
func expandTilde(_ s: String) -> String {
  if s.hasPrefix("~/") {
    let rest = String(s.dropFirst(2))
    return homeDirectory().appendingPathComponent(rest).path
  }
  return s
}
