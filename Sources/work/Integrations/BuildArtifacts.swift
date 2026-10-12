import CryptoKit
import Foundation

/// Build output a worktree leaves behind: SwiftPM `.build` directories inside
/// it, and Xcode DerivedData outside it, under
/// ~/Library/Developer/Xcode/DerivedData.
///
/// Xcode names a DerivedData directory `<Project>-<hash>`, the hash derived
/// from the path of the workspace, project or package it built, and usually
/// records that path in the directory's `info.plist`. Directories are matched
/// both ways, so one without an `info.plist` is still found, as is one whose
/// worktree has since been removed.
enum BuildArtifacts {
  static var derivedDataRoot: String {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    return "\(home)/Library/Developer/Xcode/DerivedData"
  }

  /// Xcode's DerivedData hash of `path`: its MD5 digest, each 8-byte half
  /// read big-endian and spelled as 14 base-26 letters.
  static func derivedDataHash(_ path: String) -> String {
    let digest = Array(Insecure.MD5.hash(data: Data(path.utf8)))
    func half(_ bytes: ArraySlice<UInt8>) -> String {
      var value = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
      var letters: [Character] = []
      for _ in 0..<14 {
        letters.append(Character(UnicodeScalar(UInt8(97 + value % 26))))
        value /= 26
      }
      return String(letters.reversed())
    }
    return half(digest[0..<8]) + half(digest[8..<16])
  }

  /// The paths Xcode may have built for a worktree: each `.xcworkspace` and
  /// `.xcodeproj` at its root, and the worktree itself, as for a package.
  /// Names come from the worktree, or from the main checkout once the
  /// worktree is gone.
  static func projectPaths(worktree: String, mainCheckout: String) -> [String] {
    let fm = FileManager.default
    let source = fm.fileExists(atPath: worktree) ? worktree : mainCheckout
    let names = ((try? fm.contentsOfDirectory(atPath: source)) ?? [])
      .filter { $0.hasSuffix(".xcworkspace") || $0.hasSuffix(".xcodeproj") }
      .sorted()
    return names.map { "\(worktree)/\($0)" } + [worktree]
  }

  /// DerivedData directories built from `worktree`.
  static func derivedData(worktree: String, mainCheckout: String, root: String = derivedDataRoot)
    -> [String]
  {
    var found: [String] = []
    for path in projectPaths(worktree: worktree, mainCheckout: mainCheckout) {
      let name = (URL(fileURLWithPath: path).lastPathComponent as NSString).deletingPathExtension
      let directory = "\(root)/\(name)-\(derivedDataHash(path))"
      if FileManager.default.fileExists(atPath: directory) { found.append(directory) }
    }
    for (directory, workspace) in recordedWorkspaces(root: root)
    where workspace == worktree || workspace.hasPrefix(worktree + "/") {
      if !found.contains(directory) { found.append(directory) }
    }
    return found
  }

  /// Each DerivedData directory that records the path it was built from.
  static func recordedWorkspaces(root: String = derivedDataRoot) -> [(
    directory: String, workspace: String
  )] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
    return names.sorted().compactMap { name in
      let directory = "\(root)/\(name)"
      guard let workspace = info(directory)?["WorkspacePath"] as? String else { return nil }
      return (directory, workspace)
    }
  }

  /// SwiftPM build directories in a worktree: at its root, and one level
  /// down for packages kept in a subdirectory.
  static func buildDirectories(worktree: String) -> [String] {
    let fm = FileManager.default
    var found: [String] = []
    if fm.fileExists(atPath: "\(worktree)/.build") { found.append("\(worktree)/.build") }
    for child in ((try? fm.contentsOfDirectory(atPath: worktree)) ?? []).sorted()
    where !child.hasPrefix(".") {
      let candidate = "\(worktree)/\(child)/.build"
      if fm.fileExists(atPath: candidate) { found.append(candidate) }
    }
    return found
  }

  /// When any of `paths` was last built: the newest modification among each
  /// path and the two levels below it, where builds write, and Xcode's
  /// last-accessed date for DerivedData.
  static func lastActivity(_ paths: [String]) -> Date? {
    let fm = FileManager.default
    func modified(_ path: String) -> Date? {
      (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
    var dates: [Date] = []
    for path in paths {
      if let date = info(path)?["LastAccessedDate"] as? Date { dates.append(date) }
      dates += [modified(path)].compactMap { $0 }
      for child in (try? fm.contentsOfDirectory(atPath: path)) ?? [] {
        let childPath = "\(path)/\(child)"
        dates += [modified(childPath)].compactMap { $0 }
        for grandchild in (try? fm.contentsOfDirectory(atPath: childPath)) ?? [] {
          dates += [modified("\(childPath)/\(grandchild)")].compactMap { $0 }
        }
      }
    }
    return dates.max()
  }

  /// Bytes `path` takes on disk.
  static func size(_ path: String) -> Int64 {
    guard
      let enumerator = FileManager.default.enumerator(
        at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
    else { return 0 }
    var total: Int64 = 0
    for case let url as URL in enumerator {
      total += Int64(
        (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize
          ?? 0)
    }
    return total
  }

  /// Removes each path, printing it with its size. Returns the bytes freed.
  @discardableResult
  static func remove(_ paths: [String]) -> Int64 {
    var freed: Int64 = 0
    for path in paths {
      let bytes = size(path)
      do {
        try FileManager.default.removeItem(atPath: path)
        freed += bytes
        print("Removed \(path) (\(formatBytes(bytes)))")
      } catch {
        ewrite("warning: could not remove \(path): \(error.localizedDescription)")
      }
    }
    return freed
  }

  static func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private static func info(_ directory: String) -> [String: Any]? {
    guard let data = FileManager.default.contents(atPath: "\(directory)/info.plist") else {
      return nil
    }
    return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
  }
}
