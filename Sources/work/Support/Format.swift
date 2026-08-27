import Foundation

extension String {
  /// Trim leading/trailing ASCII whitespace + newlines, matching Rust's
  /// `str::trim` for the shell-output cases here.
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Left-justify to a minimum width without truncating — the semantics of
/// Rust's `{:<width}` format spec.
func leftpad(_ s: String, _ width: Int) -> String {
  s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

/// Write a line to stderr, the analog of Rust's `eprintln!`.
func ewrite(_ line: String) {
  FileHandle.standardError.write(Data((line + "\n").utf8))
}
