import Foundation

/// Port of src/integrations/git.rs. Status-only checks capture (and discard)
/// output; user-facing mutating commands inherit stdio so git's own output
/// shows through, matching the Rust `.status()` calls.
enum Git {
    static func inRepo() -> Bool {
        (try? Shell.capture("git", ["rev-parse", "--is-inside-work-tree"]))?.succeeded ?? false
    }

    static func branchExists(_ branch: String) -> Bool {
        (try? Shell.capture("git", ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"]))?
            .succeeded ?? false
    }

    static func worktreeAdd(_ path: String, _ branch: String) throws {
        if try Shell.run("git", ["worktree", "add", path, branch]) != 0 {
            throw WorkError("git worktree add \(path) \(branch) failed")
        }
    }

    static func worktreeAddNewBranch(_ path: String, _ branch: String) throws {
        if try Shell.run("git", ["worktree", "add", "-b", branch, path]) != 0 {
            throw WorkError("git worktree add -b \(branch) \(path) failed")
        }
    }

    static func worktreeRemove(_ path: String) throws {
        if try Shell.run("git", ["worktree", "remove", path]) != 0 {
            throw WorkError("git worktree remove \(path) failed")
        }
    }

    static func worktreeClean(_ path: String) throws {
        if try Shell.run("git", ["-C", path, "clean", "-fdX"]) != 0 {
            throw WorkError("git clean -fdX in \(path) failed")
        }
    }

    static func branchDeleteForce(_ branch: String) throws {
        if try Shell.run("git", ["branch", "-D", branch]) != 0 {
            throw WorkError("git branch -D \(branch) failed")
        }
    }

    static func fetch() throws {
        if try Shell.run("git", ["fetch"]) != 0 {
            throw WorkError("git fetch failed")
        }
    }

    static func currentBranch() throws -> String {
        let out = try Shell.capture("git", ["branch", "--show-current"])
        if !out.succeeded {
            throw WorkError("git branch --show-current failed")
        }
        return out.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Look up a local branch whose last `/`-segment contains the slug. Used by
    /// `finish --coder` to recover the full topic branch from a workspace name.
    static func findBranchBySuffix(_ slug: String) -> String? {
        guard let out = try? Shell.capture("git", ["for-each-ref", "--format=%(refname:short)", "refs/heads/"]),
              out.succeeded
        else {
            return nil
        }
        let matches = out.stdoutString
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { line in
                let last = line.split(separator: "/").last.map(String.init) ?? line
                return last.contains(slug)
            }
        if matches.count > 1 {
            FileHandle.standardError.write(Data(
                "warning: multiple local branches match `\(slug)`: \(matches.joined(separator: ", ")). Using first.\n".utf8
            ))
        }
        return matches.first
    }

    /// Default branch via origin/HEAD, falling back to whichever of
    /// {master, main} exists locally. nil if neither can be determined.
    static func defaultBranch() -> String? {
        if let out = try? Shell.capture("git", ["symbolic-ref", "refs/remotes/origin/HEAD"]),
           out.succeeded
        {
            let s = out.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "refs/remotes/origin/"
            if s.hasPrefix(prefix) {
                let rest = String(s.dropFirst(prefix.count))
                if !rest.isEmpty {
                    return rest
                }
            }
        }
        for candidate in ["master", "main"] where branchExists(candidate) {
            return candidate
        }
        return nil
    }

    static func checkout(_ branch: String) throws {
        if try Shell.run("git", ["checkout", branch]) != 0 {
            throw WorkError("git checkout \(branch) failed")
        }
    }

    static func pullFFOnly() throws {
        if try Shell.run("git", ["pull", "--ff-only"]) != 0 {
            throw WorkError("git pull --ff-only failed")
        }
    }
}
