import CoreGraphics

/// Arrow-key navigation between rectangles (displays in Screen mode, Window Picker cells in Window mode).
public enum DirectionalNavigation {
    /// The candidate to move to when an arrow key is pressed while `current` is selected.
    ///
    /// A candidate qualifies when its centre is more than 1 pt away from `current`'s centre along the
    /// arrow's axis, in the arrow's direction. Among those, the one with the lowest
    /// `along + 2 × across` score wins (so a roughly aligned neighbour beats a nearer diagonal one);
    /// ties go to the earlier candidate. `current` itself (or anything at the same position) never
    /// qualifies, so it is fine to pass it in `candidates`. Returns nil when nothing lies that way.
    public static func nearest<ID>(from current: CGRect, in candidates: [(ID, CGRect)],
                                   direction: ArrowDirection) -> ID? {
        let originX = current.midX
        let originY = current.midY
        var best: (id: ID, score: CGFloat)?
        for (id, rect) in candidates {
            let dx = rect.midX - originX
            let dy = rect.midY - originY
            let along: CGFloat
            let across: CGFloat
            switch direction {
            case .left: (along, across) = (-dx, abs(dy))
            case .right: (along, across) = (dx, abs(dy))
            case .up: (along, across) = (-dy, abs(dx))
            case .down: (along, across) = (dy, abs(dx))
            }
            guard along > 1 else { continue }
            let score = along + 2 * across
            if let current = best, score >= current.score { continue }
            best = (id, score)
        }
        return best?.id
    }
}
