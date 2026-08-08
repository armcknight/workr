# workr

Worktree, tmux session, and pluggable cloud-devbox manager. A Swift port of a personal fish function.

Shipped as a binary-only Homebrew cask: built binaries are uploaded to releases on `armcknight/homebrew-tools` and installed via cask. Apple Silicon only (`aarch64-apple-darwin`).

## Install

```
brew install --cask armcknight/tools/work
```

First time on the tap:

```
brew tap armcknight/tools
brew trust armcknight/tools   # third-party taps require explicit trust
```

### Local dev build

```
make install       # builds release, drops binary at $(brew --prefix)/bin/work (shadows the cask)
make uninstall     # removes it and reinstalls the cask
```

Or plain SwiftPM:

```
swift build -c release   # binary at .build/release/work
swift test               # run the unit tests
```

The binary is named `work`. The Swift package / repo is named `workr` only because `work` is a common name. Requires a Swift 6 toolchain (macOS 13+).

## Releasing

The `release` GitHub Actions workflow runs on every numeric tag push (e.g. `0.1.1`, `0.1.1-rc.1`). It:

1. Builds `swift build -c release` on `macos-15` (arm64 runner)
2. Verifies the `version:` in `Sources/work/CLI/Work.swift` matches the base of the tag
3. Tarballs `.build/release/work` as `work-<tag>-aarch64-apple-darwin.tar.gz`
4. Creates a release on `armcknight/homebrew-tools` and uploads the tarball
5. Updates the appropriate cask in that tap and pushes:
   - tag `X.Y.Z` → `Casks/work.rb` (stable channel — what `brew install --cask work` gets)
   - tag `X.Y.Z-rc.N` → `Casks/work-rc.rb` (release-candidate channel — opt-in via `brew install --cask armcknight/tools/work-rc`)

### Cutting releases

Run from the workr repo (requires `vrsn` on PATH, from the `armcknight/tools` cask):

```
make patch        # 0.1.0 → 0.1.1 in Work.swift, commit
make minor        # 0.1.0 → 0.2.0
make major        # 0.1.0 → 1.0.0
make deploy-beta  # tags <current-version>-rc.N where N auto-increments
make deploy       # tags <current-version> (a final release)
```

Typical RC cycle:

```
make patch        # bump to 0.1.1
make deploy-beta  # tag 0.1.1-rc.1, push — workflow ships to work-rc cask
make deploy-beta  # tag 0.1.1-rc.2 — workflow bumps work-rc again
make deploy       # tag 0.1.1 — workflow ships to stable work cask
```

Test RCs locally with:

```
brew install --cask armcknight/tools/work-rc
```

(`work` and `work-rc` casks are marked `conflicts_with` each other, so brew won't let you have both installed at once.)

### One-time secret setup

The workflow needs a `TAP_RELEASE_TOKEN` repo secret on `workr`. Create a **fine-grained personal access token** with:

- **Repository access**: `armcknight/homebrew-tools` only
- **Permissions**:
  - `Contents`: Read and write (for `git push` of the cask bump + creating releases)
  - `Metadata`: Read-only (auto-granted)

Add it at `Settings → Secrets and variables → Actions → New repository secret` with name `TAP_RELEASE_TOKEN`.

## Configuration

Defaults are baked in. Override by dropping a TOML file at `~/.config/work/config.toml`. See `config.example.toml` for the full shape.

## Subcommands

Local worktrees:
- `work start <branch>` — create a worktree and tmux session
- `work term` — attach the tmux session for the current branch
- `work finish <branch>` — tear down the worktree

Cloud devboxes (via a pluggable provider — see below):
- `work start --provider <name> <branch>` / `work finish --provider <name> <branch>`
- `work remote status` / `log` / `prompt` / `test` (provider from `[remote]
  provider`, or `--provider <name>`)
- Per-invocation provider param override via `--param key=value` (repeatable)

## Architecture

`work` does two things behind one CLI, and the second is fully pluggable.

- **Local worktrees** (`start` / `term` / `finish`, no `--provider`): create a
  git worktree, symlink env files into it, run a post-create command, and open
  a tmuxinator session. Entirely self-contained.
- **Remote devboxes** (`--provider <name>`, `work remote …`): provision and
  drive a cloud dev environment. **`work` itself contains no knowledge of any
  specific cloud provider** — that lives in out-of-tree plugins.

### The provider plugin contract

A provider is a separate executable named `work-remote-<name>`, discovered on
your `PATH` (or at an explicit `[remote] path`). `work` talks to it over a
small JSON-over-stdio protocol defined by the **`WorkRemoteContract`** library
product in this repo: for each operation `work` runs `work-remote-<name> <op>`,
writes a JSON request on stdin, and reads a JSON response on stdout (streaming
ops like `start` and `log` inherit the terminal instead).

The operations are `describe` (capabilities + where repos are checked out in
the box), `slug`, `exists`, `start`, `finish`, `status`, `log`, `prompt`, and
`test`. `work` owns everything provider-agnostic — Linear ticket lookup,
bootstrap-prompt assembly, PR annotation via `gh`, the status table, and
contract-version negotiation — and delegates only the provider-specific
mechanics (create / teardown / deliver / stream) to the plugin. Provider
settings (templates, hosts, ports, credentials) live in the plugin's own
config file, never in `work`'s.

### Writing a provider

Depend on the `WorkRemoteContract` library, implement the ops it defines, and
ship an executable named `work-remote-<yourname>`. Set `[remote] provider =
"<yourname>"` (or pass `--provider <yourname>`). No changes to `work` itself
are needed — a new provider is purely additive and out-of-tree.

## License

Apache-2.0. See `LICENSE`.
