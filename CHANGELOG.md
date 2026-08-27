# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `work term` and `work start` now hand the terminal to tmux with `exec` instead
  of spawning it. `Foundation.Process` puts the child in a new process group and
  nothing makes that group foreground, so the kernel delivered `SIGWINCH` to
  `work` and never to tmux — resizing the terminal window left the tmux session
  at its old size until you detached and reattached. The Rust implementation was
  unaffected, because `Command::status()` lets the child inherit the process
  group.
- `work term` no longer reports "not in a git repository" mid-rebase, and now
  attaches to the branch's existing tmux session instead of spawning a duplicate
  when HEAD is detached. It checks repo membership directly (via `Git.inRepo()`)
  rather than inferring it from an empty `git branch --show-current`, which is
  also empty on any detached HEAD. Session resolution recovers the underlying
  branch from the rebase head-name, and from `BISECT_START` during a bisect (so
  each good/bad step reuses one session rather than opening a fresh one per
  commit); git state is read via `git rev-parse --git-path`, so it works in
  linked worktrees too. Merge, cherry-pick and revert stay on their branch and
  need no special handling.

## [1.0.1] 2026-08-10

### Fixed

- First published build. The 1.0.0 release was tagged but its CI release job
  failed before publishing (a signing-pipeline bug); 1.0.1 ships the Developer
  ID signed, notarized binary.

## [1.0.0] 2026-08-10

First stable release. No functional changes since 0.3.0 — the bump marks the
provider-plugin architecture, CLI surface, and config layout as stable and
committed to under semantic versioning.

### Added

- Release binaries are now Developer ID signed and notarized, so the Homebrew
  cask installs and runs without a Gatekeeper prompt.

### Changed

- CI and releases now delegate to armcknight/workflows' reusable SwiftPM
  pipelines: build + test on every push and PR, and a tag-driven signed cask
  release. Removes the bespoke in-repo release YAML.

## [0.3.0] - 2026-08-06

### Changed

- Reimplemented the entire tool in Swift (previously Rust). Same `work` binary
  and behavior; builds and releases now go through SwiftPM.
- Cloud-devbox support is now a **pluggable provider system**. Provider
  mechanics live in out-of-tree `work-remote-<name>` plugin executables that
  core drives over a JSON-over-stdio contract; workr core carries no
  provider-specific knowledge.
- Replaced the `--coder` / `--boxdev` flags and the `work coder` / `work boxdev`
  command groups with a generic `--provider <name>` (`-p`) flag and a
  `work remote <status|log|prompt|test>` group. The default provider comes from
  `[remote] provider` in config.
- Replaced `--coder-param` / `--box-param` with a single repeatable
  `--param key=value`.
- Restructured config: removed the `[coder]` / `[boxdev]` sections from core;
  added `[remote]` (`provider`, `path`) and `[project]` (`repos`).
  Provider-specific settings now live in each plugin's own config file.
- `work remote status` columns are now defined centrally by core
  (`SESSION | STATUS | AGENT | ACTIVITY | <provider extras> | PR`), so every
  provider renders a consistent layout.

### Added

- `WorkRemoteContract` SwiftPM library product defining the provider plugin
  protocol (ops, request/response types, version negotiation), depended on by
  provider plugins.
- `make help` target listing the available Makefile tasks.

### Removed

- All organization-specific values from the shipped config template and source
  (generic placeholders now); no provider or organization identity remains in
  core.

## [0.2.0] - 2026-06-24

- Built-in cloud-devbox flows (`start`/`finish`/`status`/`log`/`prompt`/
  `test`), Rust implementation.

## [0.1.0]

- Initial release: local git worktree + tmuxinator session management
  (`start`/`term`/`finish`). Rust implementation.

[0.3.0]: https://github.com/armcknight/workr/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/armcknight/workr/compare/v0.1.0...0.2.0
[0.1.0]: https://github.com/armcknight/workr/releases/tag/v0.1.0
