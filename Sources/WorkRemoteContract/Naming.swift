import Foundation

/// Error thrown when a slug's prefix-strip regex fails to compile.
public struct NamingError: Error, CustomStringConvertible {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var description: String { message }
}

/// Shared slug derivation for remote-provider plugins: strip the configured
/// prefix (first regex match), replace `/` with `-`, truncate to `maxLength`,
/// and strip trailing `-`s introduced by truncation.
public enum Naming {
  public static func slugify(_ branch: String, prefixStrip: String, maxLength: Int) throws -> String
  {
    let stripped = try stripFirstMatch(branch, pattern: prefixStrip)
    let normalized = stripped.replacingOccurrences(of: "/", with: "-")
    let truncated = String(normalized.prefix(maxLength))
    var s = Substring(truncated)
    while s.hasSuffix("-") { s = s.dropLast() }
    return String(s)
  }

  /// Remove the first regex match from `s` (matches Rust `Regex::replace(_,
  /// "")`, which replaces the first match only).
  private static func stripFirstMatch(_ s: String, pattern: String) throws -> String {
    let re: NSRegularExpression
    do {
      re = try NSRegularExpression(pattern: pattern)
    } catch {
      throw NamingError("compiling prefix_strip regex `\(pattern)`")
    }
    let range = NSRange(s.startIndex..<s.endIndex, in: s)
    guard let match = re.firstMatch(in: s, range: range),
      let r = Range(match.range, in: s)
    else {
      return s
    }
    var out = s
    out.removeSubrange(r)
    return out
  }
}
