import Foundation

/// The workr ↔ remote-provider plugin contract. A plugin is an executable
/// named `work-remote-<name>` (found on PATH or via `[remote] path`) that
/// speaks this JSON-over-stdio protocol: `work-remote-<name> <op>` reads a
/// JSON request on stdin and, for captured ops, writes a JSON response on
/// stdout. Streaming ops (start, finish, log, prompt, test) inherit stdio.
public enum WorkRemoteContract {
  /// Protocol version. Core sends this on every request; a plugin advertises
  /// the version it implements via `describe`. Bump on breaking changes.
  public static let version = 1
}

/// The operations a plugin implements, one per `work-remote-<name> <op>`.
public enum RemoteOp: String, CaseIterable, Sendable {
  case describe
  case slug
  case exists
  case start
  case finish
  case status
  case log
  case prompt
  case test
}

// MARK: - Requests (core → plugin, on stdin)

public struct DescribeRequest: Codable, Sendable {
  public var contract: Int
  public init(contract: Int = WorkRemoteContract.version) { self.contract = contract }
}

public struct BranchRequest: Codable, Sendable {
  public var contract: Int
  public var branch: String
  public init(contract: Int = WorkRemoteContract.version, branch: String) {
    self.contract = contract
    self.branch = branch
  }
}

public struct StartRequest: Codable, Sendable {
  public var contract: Int
  public var branch: String
  /// Fully-assembled bootstrap prompt (core builds it from the ticket +
  /// the provider's `describe.workspacePaths`).
  public var prompt: String
  /// Project repos (core config `[project] repos`), for providers that
  /// pre-seed branches on GitHub. Providers that don't need it ignore it.
  public var repos: [String]
  /// Per-invocation provider param overrides (core `--param key=value`),
  /// opaque to core — the provider merges them over its own config defaults.
  public var params: [String: String]
  public init(
    contract: Int = WorkRemoteContract.version,
    branch: String,
    prompt: String,
    repos: [String],
    params: [String: String]
  ) {
    self.contract = contract
    self.branch = branch
    self.prompt = prompt
    self.repos = repos
    self.params = params
  }
}

public struct LogRequest: Codable, Sendable {
  public var contract: Int
  public var branch: String
  public var follow: Bool
  public init(contract: Int = WorkRemoteContract.version, branch: String, follow: Bool) {
    self.contract = contract
    self.branch = branch
    self.follow = follow
  }
}

public struct PromptRequest: Codable, Sendable {
  public var contract: Int
  public var branch: String
  public var text: String
  public init(contract: Int = WorkRemoteContract.version, branch: String, text: String) {
    self.contract = contract
    self.branch = branch
    self.text = text
  }
}

public struct TestRequest: Codable, Sendable {
  public var contract: Int
  public var branch: String
  /// Port to forward; nil means the provider's own default.
  public var port: Int?
  public init(contract: Int = WorkRemoteContract.version, branch: String, port: Int?) {
    self.contract = contract
    self.branch = branch
    self.port = port
  }
}

// MARK: - Responses (plugin → core, on stdout)

public struct DescribeResponse: Codable, Sendable {
  /// Contract version this plugin implements.
  public var contract: Int
  /// Paths inside the remote env where repos are checked out — core folds
  /// these into the bootstrap prompt's "working environment" section.
  public var workspacePaths: [String]
  public init(contract: Int = WorkRemoteContract.version, workspacePaths: [String]) {
    self.contract = contract
    self.workspacePaths = workspacePaths
  }
}

public struct SlugResponse: Codable, Sendable {
  public var slug: String
  public init(slug: String) { self.slug = slug }
}

public struct ExistsResponse: Codable, Sendable {
  public var exists: Bool
  public init(exists: Bool) { self.exists = exists }
}

/// One row of `status` output. Plugins fill the canonical semantic fields;
/// **core owns their display headers and order** (see `StatusColumns`), so the
/// layout is consistent across providers. `extras` are genuinely
/// provider-specific trailing columns (e.g. a dashboard URL) that core appends
/// verbatim. `name` is the identifier core uses to match PRs.
public struct StatusRow: Codable, Sendable {
  public var name: String
  /// Lifecycle state of the session (e.g. running / stopped). Header: STATUS.
  public var status: String
  /// Agent state (e.g. the in-session agent's status). Header: AGENT.
  public var agent: String
  /// Recent activity / last-activity summary. Header: ACTIVITY.
  public var activity: String
  /// Provider-specific trailing columns, rendered after the canonical ones.
  public var extras: [StatusColumn]

  public init(
    name: String, status: String, agent: String, activity: String, extras: [StatusColumn] = []
  ) {
    self.name = name
    self.status = status
    self.agent = agent
    self.activity = activity
    self.extras = extras
  }
}

public struct StatusColumn: Codable, Sendable {
  public var header: String
  public var value: String
  public init(header: String, value: String) {
    self.header = header
    self.value = value
  }
}

/// Core-owned display headers + order for the canonical status columns. This is
/// the single source of truth for status-table naming across all providers.
public enum StatusColumns {
  public static let name = "SESSION"
  public static let status = "STATUS"
  public static let agent = "AGENT"
  public static let activity = "ACTIVITY"

  /// Canonical headers in render order (before provider extras and PR).
  public static let canonical = [name, status, agent, activity]
}

// MARK: - Plugin-side IO helpers

/// Helpers a plugin's `main` uses to read the request and write the response.
public enum ContractIO {
  /// Decode the JSON request from stdin.
  public static func readRequest<T: Decodable>(_ type: T.Type) throws -> T {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return try JSONDecoder().decode(T.self, from: data)
  }

  /// Encode a JSON response to stdout (compact, no trailing newline).
  public static func writeResponse<T: Encodable>(_ value: T) throws {
    let data = try JSONEncoder().encode(value)
    FileHandle.standardOutput.write(data)
  }

  /// Validate the request's contract version against what this plugin
  /// implements, exiting with a clear message on mismatch.
  public static func requireContract(_ got: Int) {
    if got != WorkRemoteContract.version {
      FileHandle.standardError.write(
        Data(
          "contract version mismatch: core sent \(got), plugin implements \(WorkRemoteContract.version)\n"
            .utf8
        ))
      exit(75)  // EX_TEMPFAIL — core surfaces this
    }
  }
}
