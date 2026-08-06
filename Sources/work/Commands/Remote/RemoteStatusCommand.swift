import Foundation
import WorkRemoteContract

/// `work remote status`: plugins fill canonical semantic fields; core owns the
/// canonical headers, appends provider extras + a PR column, and renders one
/// unified table.
enum RemoteStatusCommand {
    static func run(_ cfg: Config, provider: String) throws {
        let runner = try PluginRunner.resolve(provider: provider, config: cfg)
        let rows = try runner.status()
        if rows.isEmpty {
            print("No remote sessions found")
            return
        }

        var prs: [JSON] = []
        if Shell.which("gh") {
            for repo in cfg.project.repos {
                prs += GitHub.listUserPRs(repo: repo, fields: cfg.github.prFields)
            }
        }

        let extraHeaders = rows[0].extras.map(\.header)
        let headers = StatusColumns.canonical + extraHeaders + ["PR"]
        let tableRows = rows.map { row in
            [row.name, row.status, row.agent, row.activity]
                + row.extras.map(\.value)
                + [PRAnnotation.annotate(row.name, prs)]
        }
        Table.render(headers: headers, rows: tableRows)
    }
}
