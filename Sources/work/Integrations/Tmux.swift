import Foundation

/// Port of src/integrations/tmux.rs.
enum Tmux {
    static func hasSession(_ name: String) -> Bool {
        (try? Shell.capture("tmux", ["has-session", "-t", name]))?.succeeded ?? false
    }

    /// Attach to an existing session; the tmux client takes over the terminal.
    ///
    /// exec rather than spawn, so the client inherits this process group and
    /// therefore receives SIGWINCH. See `Shell.exec`.
    static func attachSession(_ name: String) throws -> Never {
        try Shell.exec("tmux", ["attach-session", "-t", name])
    }

    static func killSession(_ name: String) throws {
        if try Shell.run("tmux", ["kill-session", "-t", name]) != 0 {
            throw WorkError("tmux kill-session -t \(name) failed")
        }
    }

    /// Start a new session from a tmuxinator config, which attaches at the end.
    ///
    /// exec for the same reason as `attachSession`: tmuxinator's generated script
    /// runs `tmux attach-session` in this process group, so the client lands in
    /// the terminal's foreground group.
    static func tmuxinatorStart(config: String, sessionName: String) throws -> Never {
        try Shell.exec("tmuxinator", ["start", config, "-n", sessionName])
    }

    /// Build the session name from a pwd slug + a branch slug, mirroring the
    /// original fish behavior so existing sessions keep their old names.
    static func sessionName(pwd: String, branch: String) -> String {
        "\(slugifyPwd(pwd))_\(slugifyBranch(branch))"
    }

    /// Replace '/' with '-', strip dots, trim leading/trailing '-', lowercase.
    static func slugifyPwd(_ s: String) -> String {
        let replaced = s.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "")
        return replaced
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
    }

    static func slugifyBranch(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").lowercased()
    }
}
