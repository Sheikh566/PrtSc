/// Runs async operations one at a time, in the order `run` was called. A later operation starts only
/// after every earlier one has finished, so work that suspends (encoding, notification posting) can't
/// be overtaken by a newer request. Used by OutputService so the clipboard always ends up holding the
/// newest capture and files are saved in request order.
@MainActor
final class SerialTaskQueue {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @escaping @MainActor () async -> T) async -> T {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await operation()
        }
        tail = Task { @MainActor in _ = await task.value }
        return await task.value
    }
}
