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

## Remote providers (plugins)

Cloud-devbox mechanics live in out-of-tree **plugin executables** named
`work-remote-<name>` on your `PATH` (or an explicit `[remote] path`). workr
core carries no provider-specific knowledge; it speaks a small JSON-over-stdio
contract (see the `WorkRemoteContract` library product) to whichever plugin is
selected. Provider-specific settings live in the plugin's own config, not in
workr's. To add a provider, ship a `work-remote-<name>` binary implementing
the contract.

## License

Apache-2.0. See `LICENSE`.
