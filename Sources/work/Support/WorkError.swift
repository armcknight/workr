import Foundation

/// General-purpose error carrying a human-readable message, the Swift analog
/// of the Rust code's `anyhow::bail!` / `anyhow!` usage. Printed by
/// ArgumentParser as `Error: <message>` on exit.
struct WorkError: Error, CustomStringConvertible {
  let message: String
  init(_ message: String) { self.message = message }
  var description: String { message }
}
