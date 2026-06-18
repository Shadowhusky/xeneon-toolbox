import Foundation

/// A 4×4 2048 board. Moves are deterministic and pure; spawning new tiles is
/// explicit so the engine can be tested without randomness.
public struct Game2048 {
    public enum Move { case left, right, up, down }

    public private(set) var grid: [[Int]]
    public private(set) var score: Int
    public let size = 4

    public init() {
        grid = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        score = 0
    }

    public init(_ grid: [[Int]]) {
        self.grid = grid
        self.score = 0
    }

    /// Collapse one row toward index 0: slide non-zeros, merge equal adjacent
    /// pairs once, left to right. Returns the new row and points gained.
    public static func collapseLeft(_ row: [Int]) -> (row: [Int], gained: Int) {
        let tiles = row.filter { $0 != 0 }
        var result: [Int] = []
        var gained = 0
        var i = 0
        while i < tiles.count {
            if i + 1 < tiles.count && tiles[i] == tiles[i + 1] {
                let merged = tiles[i] * 2
                result.append(merged)
                gained += merged
                i += 2
            } else {
                result.append(tiles[i])
                i += 1
            }
        }
        result.append(contentsOf: Array(repeating: 0, count: row.count - result.count))
        return (result, gained)
    }

    @discardableResult
    public mutating func move(_ m: Move) -> Bool {
        let before = grid
        var rows = orient(grid, for: m)
        var gained = 0
        rows = rows.map { r in
            let c = Self.collapseLeft(r)
            gained += c.gained
            return c.row
        }
        grid = unorient(rows, for: m)
        score += gained
        return grid != before
    }

    public func emptyCells() -> [(Int, Int)] {
        var cells: [(Int, Int)] = []
        for r in 0..<4 { for c in 0..<4 where grid[r][c] == 0 { cells.append((r, c)) } }
        return cells
    }

    public mutating func spawn(value: Int, at cell: (Int, Int)) {
        grid[cell.0][cell.1] = value
    }

    public var isGameOver: Bool {
        if !emptyCells().isEmpty { return false }
        for m in [Move.left, .right, .up, .down] {
            var copy = self
            if copy.move(m) { return false }
        }
        return true
    }

    // Reorient the grid so every move becomes a "collapse left".
    private func orient(_ g: [[Int]], for m: Move) -> [[Int]] {
        switch m {
        case .left: return g
        case .right: return g.map { $0.reversed() }
        case .up: return transpose(g)
        case .down: return transpose(g).map { $0.reversed() }
        }
    }

    private func unorient(_ g: [[Int]], for m: Move) -> [[Int]] {
        switch m {
        case .left: return g
        case .right: return g.map { $0.reversed() }
        case .up: return transpose(g)
        case .down: return transpose(g.map { $0.reversed() })
        }
    }

    private func transpose(_ g: [[Int]]) -> [[Int]] {
        var t = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        for r in 0..<4 { for c in 0..<4 { t[c][r] = g[r][c] } }
        return t
    }
}
