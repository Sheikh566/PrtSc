import Observation

/// Runs `apply` now and again every time an `@Observable` value it read changes.
@MainActor
func observeForever(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        Task { @MainActor in observeForever(apply) }
    }
}
