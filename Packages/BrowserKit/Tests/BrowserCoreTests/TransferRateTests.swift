import Testing
@testable import BrowserCore

// Failure modes:
// 1. A first burst reads as a huge speed and a near-zero time left.
// 2. An old fast stretch keeps the speed high after the connection slows down.
// 3. A transfer that starts over (resumed without resume data) gives a negative speed.
// 4. A time left is given without a size, or with no progress (division by zero).

@Test func noSpeedBeforeTheSamplesSpanASecond() {
    var rate = TransferRate()
    #expect(rate.bytesPerSecond == nil)
    rate.record(bytes: 0, at: 10)
    rate.record(bytes: 5_000_000, at: 10.2)
    #expect(rate.bytesPerSecond == nil)
    #expect(rate.remaining(totalBytes: 10_000_000) == nil)
}

@Test func speedAndTimeLeftFollowASteadyTransfer() {
    var rate = TransferRate()
    for second in 0...3 { rate.record(bytes: Int64(second) * 1_000_000, at: Double(second)) }
    #expect(rate.bytesPerSecond == 1_000_000)
    #expect(rate.remaining(totalBytes: 10_000_000) == .seconds(7))
    #expect(rate.remaining(totalBytes: 2_500_000) == .zero, "A size below the bytes received leaves no time")
}

@Test func speedForgetsSamplesOlderThanTheWindow() {
    var rate = TransferRate()
    // A fast first stretch, then a slow one longer than the window.
    rate.record(bytes: 0, at: 0)
    rate.record(bytes: 50_000_000, at: 1)
    for second in 2...10 { rate.record(bytes: 50_000_000 + Int64(second - 1) * 100_000, at: Double(second)) }
    #expect(rate.bytesPerSecond == 100_000)
}

@Test func startingOverDropsEarlierSamples() {
    var rate = TransferRate()
    rate.record(bytes: 0, at: 0)
    rate.record(bytes: 4_000_000, at: 2)
    rate.record(bytes: 1_000, at: 3)
    #expect(rate.bytesPerSecond == nil)
    rate.record(bytes: 2_001_000, at: 5)
    #expect(rate.bytesPerSecond == 1_000_000)
}

@Test func noTimeLeftWithoutSizeOrProgress() {
    var rate = TransferRate()
    rate.record(bytes: 1_000, at: 0)
    rate.record(bytes: 1_000, at: 2)
    #expect(rate.bytesPerSecond == 0)
    #expect(rate.remaining(totalBytes: 5_000) == nil)
    rate.record(bytes: 3_000, at: 3)
    #expect(rate.remaining(totalBytes: nil) == nil)
}
