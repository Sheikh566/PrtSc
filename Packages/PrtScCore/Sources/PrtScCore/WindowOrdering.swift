/// Z-order helpers for window lists.
public enum WindowOrdering {
    /// `items` sorted front to back. `zOrder` maps a window ID to its position in the system's
    /// front-to-back window list (0 = front-most). Windows missing from `zOrder` go last; windows
    /// with equal (or no) position keep their input order.
    public static func frontToBack<T>(_ items: [T], windowID: (T) -> UInt32, zOrder: [UInt32: Int]) -> [T] {
        items.enumerated().sorted { lhs, rhs in
            let l = zOrder[windowID(lhs.element)] ?? Int.max
            let r = zOrder[windowID(rhs.element)] ?? Int.max
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }
}
