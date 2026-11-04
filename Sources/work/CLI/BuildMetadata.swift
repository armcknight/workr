extension Work {
  /// The version with semver build metadata appended when there is any, so a
  /// local build reads as e.g. `1.2.0+d0a4bc2.dirty` and a release as `1.2.0`.
  static var fullVersion: String {
    buildMetadata.map { "\(version)+\($0)" } ?? version
  }
}

// `make install` compiles with WORK_DEV_BUILD and generates
// BuildMetadata.generated.swift, which defines `buildMetadata` from the git
// hash. Every other build, including the release workflow's, gets none.
#if !WORK_DEV_BUILD
  extension Work {
    static let buildMetadata: String? = nil
  }
#endif
