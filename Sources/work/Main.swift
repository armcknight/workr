import Foundation

@main
enum Main {
    static func main() {
        // Line-buffer stdout so our `print`s interleave correctly with the
        // inherited stdout of child processes (git, tmux, etc.). Mirrors Rust's
        // stdout, which uses a LineWriter that flushes on every newline.
        setvbuf(stdout, nil, _IOLBF, 0)
        Work.main()
    }
}
