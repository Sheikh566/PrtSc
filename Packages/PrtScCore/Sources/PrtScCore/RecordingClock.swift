import Foundation

public enum RecordingClock {
    /// The Recording Indicator's elapsed time: "m:ss" under an hour, "h:mm:ss" from one hour on.
    /// Whole seconds, rounded down. Negative, NaN and infinite values show "0:00".
    public static func format(elapsed: TimeInterval) -> String {
        guard elapsed.isFinite, elapsed > 0 else { return "0:00" }
        // Clamp so absurd values can't trap in the Int conversion.
        let total = Int(min(elapsed.rounded(.down), 1_000_000_000_000))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
