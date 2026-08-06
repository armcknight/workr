import Foundation
import WorkRemoteContract

/// Drives a remote-provider plugin over the JSON-stdio contract. Captured ops
/// pipe a JSON request in and decode a JSON response; streaming ops pipe the
/// request in and inherit stdout/stderr so provider progress reaches the user.
struct PluginRunner {
    /// Executable name (`work-remote-<provider>`, resolved on PATH by env) or
    /// an explicit absolute path from `[remote] path`.
    let executable: String
    let provider: String

    /// Resolve the plugin for `provider`. Prefers `[remote] path`; otherwise
    /// requires `work-remote-<provider>` on PATH.
    static func resolve(provider: String, config: Config) throws -> PluginRunner {
        let name = provider.isEmpty ? config.remote.provider : provider
        guard !name.isEmpty else {
            throw WorkError("no remote provider configured (set [remote] provider in config, or pass --remote <name>)")
        }
        if !config.remote.path.isEmpty {
            return PluginRunner(executable: config.remote.path, provider: name)
        }
        let exe = "work-remote-\(name)"
        guard Shell.which(exe) else {
            throw WorkError("no plugin for remote '\(name)' (expected `\(exe)` on PATH, or set [remote] path)")
        }
        return PluginRunner(executable: exe, provider: name)
    }

    // MARK: - Captured ops

    func describe() throws -> DescribeResponse {
        try capture(.describe, DescribeRequest())
    }

    func exists(branch: String) throws -> Bool {
        let res: ExistsResponse = try capture(.exists, BranchRequest(branch: branch))
        return res.exists
    }

    func status() throws -> [StatusRow] {
        try capture(.status, DescribeRequest())
    }

    // MARK: - Streaming ops

    func start(branch: String, prompt: String, repos: [String], params: [String: String]) throws {
        try stream(.start, StartRequest(branch: branch, prompt: prompt, repos: repos, params: params))
    }

    func finish(branch: String) throws {
        try stream(.finish, BranchRequest(branch: branch))
    }

    func log(branch: String, follow: Bool) throws {
        try stream(.log, LogRequest(branch: branch, follow: follow))
    }

    func prompt(branch: String, text: String) throws {
        try stream(.prompt, PromptRequest(branch: branch, text: text))
    }

    func test(branch: String, port: Int?) throws {
        try stream(.test, TestRequest(branch: branch, port: port))
    }

    // MARK: - Transport

    private func capture<Req: Encodable, Res: Decodable>(_ op: RemoteOp, _ req: Req) throws -> Res {
        let data = try JSONEncoder().encode(req)
        let out: CommandOutput
        do {
            out = try Shell.capture(executable, [op.rawValue], stdin: data)
        } catch {
            throw WorkError("running remote '\(provider)' \(op.rawValue): \(error)")
        }
        if !out.succeeded {
            throw WorkError("remote '\(provider)' \(op.rawValue) failed: \(out.stderrString.trimmed)")
        }
        do {
            return try JSONDecoder().decode(Res.self, from: out.stdout)
        } catch {
            throw WorkError("remote '\(provider)' \(op.rawValue) returned malformed output: \(error)")
        }
    }

    private func stream<Req: Encodable>(_ op: RemoteOp, _ req: Req) throws {
        let data = try JSONEncoder().encode(req)
        let status = try Shell.runWithInput(executable, [op.rawValue], stdin: data)
        if status != 0 {
            throw WorkError("remote '\(provider)' \(op.rawValue) exited with status \(status)")
        }
    }
}
