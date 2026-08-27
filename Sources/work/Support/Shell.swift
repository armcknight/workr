import Foundation

/// Result of a captured subprocess run — the Swift analog of Rust's
/// `std::process::Output`.
struct CommandOutput {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var succeeded: Bool { status == 0 }
    var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

/// Thin wrapper over `Foundation.Process` mirroring the ways the Rust code
/// shells out: capture output, run inheriting stdio, run with piped stdin,
/// and spawn a background child.
enum Shell {
    /// Run `tool args...`, capturing stdout+stderr and the exit status.
    /// Throws only if the process can't be launched (tool missing, etc.).
    @discardableResult
    static func capture(
        _ tool: String,
        _ args: [String],
        currentDirectory: String? = nil,
        stdin: Data? = nil
    ) throws -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        if let cwd = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let inPipe: Pipe?
        if stdin != nil {
            inPipe = Pipe()
            process.standardInput = inPipe
        } else {
            inPipe = nil
        }

        do {
            try process.run()
        } catch {
            throw WorkError("failed to launch \(tool): \(error.localizedDescription)")
        }

        if let inPipe, let stdin {
            inPipe.fileHandleForWriting.write(stdin)
            inPipe.fileHandleForWriting.closeFile()
        }

        // Read before waiting to avoid deadlock on large output.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandOutput(
            status: process.terminationStatus,
            stdout: outData,
            stderr: errData
        )
    }

    /// Run `tool args...` inheriting the parent's stdio, returning the exit
    /// status. Analog of Rust's `Command::status()`.
    @discardableResult
    static func run(
        _ tool: String,
        _ args: [String],
        currentDirectory: String? = nil
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        if let cwd = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        do {
            try process.run()
        } catch {
            throw WorkError("failed to launch \(tool): \(error.localizedDescription)")
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Replace this process with `tool args...`, inheriting the terminal.
    ///
    /// Spawning is wrong for anything that takes over the terminal.
    /// `Foundation.Process` spawns with `POSIX_SPAWN_SETPGROUP` and pgroup 0, so
    /// the child leads a *new* process group and nothing hands it the terminal.
    /// The kernel sends SIGWINCH only to the foreground group — which stays this
    /// process — so a tmux client spawned by `run` never learns the window was
    /// resized. exec keeps the PID and the process group, so the new program is
    /// already foreground and gets the signal directly.
    ///
    /// Returns only on failure, in which case it throws.
    static func exec(_ tool: String, _ args: [String]) throws -> Never {
        // env resolves `tool` on PATH, matching how `run` and `capture` launch.
        let argv = ["/usr/bin/env", tool] + args
        var cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgs.append(nil)
        execv("/usr/bin/env", &cArgs)
        throw WorkError("failed to exec \(tool): \(String(cString: strerror(errno)))")
    }

    /// Run `tool args...` with `stdin` piped in, inheriting stdout/stderr, and
    /// wait — used to drive a streaming plugin op (the plugin reads its JSON
    /// request from stdin, then streams progress to the inherited stdout).
    @discardableResult
    static func runWithInput(_ tool: String, _ args: [String], stdin: Data) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        let inPipe = Pipe()
        process.standardInput = inPipe
        do {
            try process.run()
        } catch {
            throw WorkError("failed to launch \(tool): \(error.localizedDescription)")
        }
        inPipe.fileHandleForWriting.write(stdin)
        inPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Spawn `tool args...` as a background child inheriting stdout/stderr,
    /// returning the running `Process`. Analog of Rust's `Command::spawn()`
    /// for the port-forward tunnel.
    static func spawn(_ tool: String, _ args: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw WorkError("failed to launch \(tool): \(error.localizedDescription)")
        }
        return process
    }

    /// True if `tool` resolves on `PATH`. Analog of the `which` crate's
    /// `which(tool).is_ok()`.
    static func which(_ tool: String) -> Bool {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else {
            return false
        }
        let fm = FileManager.default
        for dir in path.split(separator: ":") {
            let candidate = "\(dir)/\(tool)"
            if fm.isExecutableFile(atPath: candidate) {
                return true
            }
        }
        return false
    }
}
