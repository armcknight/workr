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

    /// Read a file inside the repo's git dir, located via `git rev-parse
    /// --git-path` rather than assuming `.git/` — in a linked worktree `.git`
    /// is a *file* and the real state dir lives under `.git/worktrees/<name>/`
    /// in the main repo.
    private static func readGitPathFile(_ relative: String) -> String? {
        guard let out = try? Shell.capture("git", ["rev-parse", "--git-path", relative]),
              out.succeeded
        else { return nil }
        let path = out.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              let contents = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }
        let value = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func strippingHeadsPrefix(_ ref: String) -> String {
        ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
    }

    /// The branch a rebase is replaying, or nil if no rebase is running.
    ///
    /// Mid-rebase git parks you on a detached HEAD, so `branch --show-current`
    /// returns empty (with exit 0 — it is not an error). The branch being
    /// rebased is still recorded in `head-name` under the rebase state dir:
    /// `rebase-merge` for the interactive/merge backend, `rebase-apply` for
    /// the `am` backend.
    static func rebaseHeadName() -> String? {
        for dir in ["rebase-merge", "rebase-apply"] {
            if let ref = readGitPathFile("\(dir)/head-name") {
                // head-name holds a full ref, e.g. "refs/heads/topic".
                return strippingHeadsPrefix(ref)
            }
        }
        return nil
    }

    /// The branch a bisect started from, or nil if no bisect is running.
    ///
    /// Bisect is the other common operation that detaches HEAD. It matters
    /// more than a one-off detach: HEAD moves to a different commit at every
    /// `git bisect good/bad`, so keying a session off the SHA would spawn a
    /// fresh tmux session on each step. BISECT_START records where the bisect
    /// began — a branch name normally, or a raw SHA if the bisect itself
    /// started from a detached HEAD. Either way it's stable for the run.
    ///
    /// Note merge, cherry-pick, and revert conflicts do *not* need handling:
    /// they leave you on your branch, so `--show-current` answers normally.
    static func bisectStartName() -> String? {
        readGitPathFile("BISECT_START").map(strippingHeadsPrefix)
    }

    static func shortHead() -> String? {
        guard let out = try? Shell.capture("git", ["rev-parse", "--short", "HEAD"]), out.succeeded
        else { return nil }
        let sha = out.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    /// Branch name to key a tmux session off of, tolerating a detached HEAD.
    ///
    /// Callers must already have established they're in a repo — an empty
    /// result here means detached HEAD, not "no repository".
    ///
    /// During a rebase or bisect this resolves back to the branch that
    /// operation started from, so `work term` attaches to the same session it
    /// would outside the operation rather than spawning a second one. A plain
    /// detached HEAD (e.g. after `git checkout <sha>`) has no branch to
    /// recover, so it falls back to the short SHA, which at least stays stable
    /// while you're parked there.
    static func sessionBranch() throws -> String {
        let current = try currentBranch()
        if !current.isEmpty { return current }
        if let rebasing = rebaseHeadName() { return rebasing }
        if let bisecting = bisectStartName() { return bisecting }
        if let sha = shortHead() { return "detached-\(sha)" }
        throw WorkError(
            "Could not determine a branch name: HEAD is detached and no rebase state or commit was found."
        )
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
