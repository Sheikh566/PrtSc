/// Receives finished captures (the Screenshot UI and Instant Captures deliver here).
@MainActor
protocol CaptureSink: AnyObject {
    func deliver(_ capture: CapturedImage) async
}
