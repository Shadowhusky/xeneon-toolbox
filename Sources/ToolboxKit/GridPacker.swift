import Foundation

/// Where an item landed on the grid: its top-left cell and its footprint.
public struct GridSlot: Equatable, Sendable {
    public let column: Int
    public let row: Int
    public let columns: Int
    public let rows: Int

    public init(column: Int, row: Int, columns: Int, rows: Int) {
        self.column = column
        self.row = row
        self.columns = columns
        self.rows = rows
    }
}

/// An item to place, with its footprint in cells.
public struct PackedItem<ID: Hashable & Sendable>: Sendable {
    public let id: ID
    public let columns: Int
    public let rows: Int

    public init(id: ID, columns: Int, rows: Int) {
        self.id = id
        self.columns = max(1, columns)
        self.rows = max(1, rows)
    }
}

/// First-fit packing for a fixed grid: items go in order, each into the first
/// free cell (top row first, left to right) whose footprint fits. Items that
/// fit nowhere land in `overflow`, order preserved.
public enum GridPacker {
    public static func pack<ID>(_ items: [PackedItem<ID>], columns: Int, rows: Int) -> (placed: [ID: GridSlot], overflow: [ID]) {
        var taken = Array(repeating: Array(repeating: false, count: columns), count: rows)
        var placed: [ID: GridSlot] = [:]
        var overflow: [ID] = []

        func fits(_ item: PackedItem<ID>, at column: Int, _ row: Int) -> Bool {
            guard column + item.columns <= columns, row + item.rows <= rows else { return false }
            for r in row..<(row + item.rows) {
                for c in column..<(column + item.columns) where taken[r][c] { return false }
            }
            return true
        }

        for item in items {
            var slot: GridSlot?
            search: for r in 0..<rows {
                for c in 0..<columns where fits(item, at: c, r) {
                    slot = GridSlot(column: c, row: r, columns: item.columns, rows: item.rows)
                    break search
                }
            }
            guard let s = slot else { overflow.append(item.id); continue }
            for r in s.row..<(s.row + s.rows) {
                for c in s.column..<(s.column + s.columns) { taken[r][c] = true }
            }
            placed[item.id] = s
        }
        return (placed, overflow)
    }
}
