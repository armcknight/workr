import Foundation

/// A bordered table renderer with dynamic column widths (max of header and any
/// cell in that column). Values are rendered verbatim — providers pre-format /
/// truncate their own cells; core does not.
enum Table {
    static func render(headers: [String], rows: [[String]]) {
        let widths: [Int] = headers.indices.map { i in
            var w = headers[i].count
            for row in rows where i < row.count {
                w = Swift.max(w, row[i].count)
            }
            return w
        }

        print(border(widths, "┌", "┬", "┐"))
        print(line(headers, widths))
        print(border(widths, "├", "┼", "┤"))
        for row in rows {
            print(line(row, widths))
        }
        print(border(widths, "└", "┴", "┘"))
    }

    private static func border(_ widths: [Int], _ left: String, _ mid: String, _ right: String) -> String {
        var s = left
        for (i, w) in widths.enumerated() {
            s += String(repeating: "─", count: w + 2)
            s += (i + 1 == widths.count) ? right : mid
        }
        return s
    }

    private static func line(_ cells: [String], _ widths: [Int]) -> String {
        var s = "│"
        for (i, cell) in cells.enumerated() {
            let pad = Swift.max(0, widths[i] - cell.count)
            s += " " + cell + String(repeating: " ", count: pad) + " │"
        }
        return s
    }
}
