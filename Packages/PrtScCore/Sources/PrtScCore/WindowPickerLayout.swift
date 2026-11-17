import CoreGraphics
import Foundation

public enum WindowPickerLayout {
    /// Overview-style grid: aspect ratio preserved, never scaled above 1, `spacing` between cells,
    /// rows centred inside `area`. Returns one rect per input size, in input order.
    ///
    /// Windows are placed in input order, filling rows left to right. Every candidate row count
    /// (1…n) is evaluated and the one giving the largest uniform scale wins; ties go to fewer rows.
    /// All windows share that one scale, so relative sizes are preserved.
    public static func layout(sizes: [CGSize], in area: CGRect, spacing: CGFloat) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        let spacing = max(spacing, 0)
        let n = sizes.count

        var best: (scale: CGFloat, rows: [Range<Int>])?
        var seenColumnCounts = Set<Int>()
        for rowCount in 1...n {
            let columns = (n + rowCount - 1) / rowCount
            guard seenColumnCounts.insert(columns).inserted else { continue }  // same grid as a smaller rowCount
            let rows = stride(from: 0, to: n, by: columns).map { $0..<min($0 + columns, n) }
            let s = scale(sizes: sizes, rows: rows, area: area, spacing: spacing)
            if best == nil || s > best!.scale + 1e-9 { best = (s, rows) }
        }
        let (scale, rows) = best!

        let rowHeights = rows.map { row in sizes[row].map { $0.height * scale }.max() ?? 0 }
        let totalHeight = rowHeights.reduce(0, +) + spacing * CGFloat(rows.count - 1)
        var y = area.minY + (area.height - totalHeight) / 2

        var result = [CGRect](repeating: .zero, count: n)
        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = sizes[row].map { $0.width * scale }.reduce(0, +) + spacing * CGFloat(row.count - 1)
            var x = area.minX + (area.width - rowWidth) / 2
            for i in row {
                let w = sizes[i].width * scale
                let h = sizes[i].height * scale
                result[i] = CGRect(x: x, y: y + (rowHeights[rowIndex] - h) / 2, width: w, height: h)
                x += w + spacing
            }
            y += rowHeights[rowIndex] + spacing
        }
        return result
    }

    /// Largest uniform scale (≤ 1, ≥ 0) at which `rows` fit in `area` with fixed `spacing`.
    private static func scale(sizes: [CGSize], rows: [Range<Int>], area: CGRect, spacing: CGFloat) -> CGFloat {
        var scale: CGFloat = 1
        for row in rows {
            let sumWidth = sizes[row].map(\.width).reduce(0, +)
            if sumWidth > 0 {
                scale = min(scale, (area.width - spacing * CGFloat(row.count - 1)) / sumWidth)
            }
        }
        let sumHeight = rows.map { row in sizes[row].map(\.height).max() ?? 0 }.reduce(0, +)
        if sumHeight > 0 {
            scale = min(scale, (area.height - spacing * CGFloat(rows.count - 1)) / sumHeight)
        }
        return max(scale, 0)
    }
}
