import Foundation
import Testing
@testable import PrtScCore

@Suite("RecordingClock")
struct RecordingClockTests {
    @Test(arguments: [
        (0.0, "0:00"), (0.4, "0:00"), (0.999, "0:00"), (1.0, "0:01"), (9.0, "0:09"), (10.0, "0:10"),
        (59.0, "0:59"), (59.99, "0:59"), (60.0, "1:00"), (61.5, "1:01"), (125.0, "2:05"),
        (600.0, "10:00"), (3599.0, "59:59"), (3599.99, "59:59"),
    ] as [(TimeInterval, String)])
    func minutesAndSecondsUnderAnHour(elapsed: TimeInterval, expected: String) {
        #expect(RecordingClock.format(elapsed: elapsed) == expected)
    }

    @Test(arguments: [
        (3600.0, "1:00:00"), (3601.0, "1:00:01"), (3661.0, "1:01:01"), (7325.0, "2:02:05"),
        (36_000.0, "10:00:00"), (86_399.0, "23:59:59"), (90_000.0, "25:00:00"),
    ] as [(TimeInterval, String)])
    func hoursAfterAnHour(elapsed: TimeInterval, expected: String) {
        #expect(RecordingClock.format(elapsed: elapsed) == expected)
    }

    @Test(arguments: [-1.0, -0.5, -3600.0, -Double.infinity, Double.nan, Double.infinity] as [TimeInterval])
    func negativeAndNonFiniteShowZero(elapsed: TimeInterval) {
        #expect(RecordingClock.format(elapsed: elapsed) == "0:00")
    }

    @Test func absurdlyLargeValuesDoNotTrap() {
        #expect(!RecordingClock.format(elapsed: Double.greatestFiniteMagnitude).isEmpty)
    }
}
