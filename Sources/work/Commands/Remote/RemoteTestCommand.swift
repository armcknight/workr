import Foundation

enum RemoteTestCommand {
  static func run(_ cfg: Config, provider: String, branch: String, port: Int?) throws {
    let runner = try PluginRunner.resolve(provider: provider, config: cfg)
    guard try runner.exists(branch: branch) else {
      throw WorkError(
        "remote session for '\(branch)' not found. Create it with `work start --provider \(runner.provider) \(branch)`."
      )
    }
    try runner.test(branch: branch, port: port)
  }
}
