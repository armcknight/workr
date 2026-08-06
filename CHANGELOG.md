# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
