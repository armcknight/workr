import Foundation

/// Port of src/integrations/linear.rs.
enum Linear {
    /// `linctl issue get <id> --json` → parsed ticket payload.
    static func getTicket(_ id: String) throws -> JSON {
        let out: CommandOutput
        do {
            out = try Shell.capture("linctl", ["issue", "get", id, "--json"])
        } catch {
            throw WorkError("running linctl issue get: \(error)")
        }
        if !out.succeeded {
            throw WorkError("linctl issue get \(id) failed: \(out.stderrString.trimmed)")
        }
        if out.stdout.isEmpty {
            throw WorkError("linctl issue get \(id) returned empty output")
        }
        guard let v = JSON.parse(out.stdout) else {
            throw WorkError("parsing linctl issue get output as JSON")
        }
        return v
    }

    /// `linctl issue update <id> --state "<name>"`. Best-effort by design.
    static func updateState(_ id: String, _ state: String) throws {
        let out: CommandOutput
        do {
            out = try Shell.capture("linctl", ["issue", "update", id, "--state", state])
        } catch {
            throw WorkError("running linctl issue update: \(error)")
        }
        if !out.succeeded {
            throw WorkError("linctl issue update \(id) --state \"\(state)\" failed")
        }
    }
}
