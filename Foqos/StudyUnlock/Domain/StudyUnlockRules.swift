import Foundation

enum StudyUnlockRules {
  static let minutesRange = 5...60
  static let defaultMinutes = 15

  static func clampedMinutes(_ minutes: Int) -> Int {
    min(max(minutes, minutesRange.lowerBound), minutesRange.upperBound)
  }

  // DeviceActivity schedules end on a whole second; the stored expiry matches that end.
  static func expiry(from now: Date, minutes: Int) -> Date {
    let end = now.timeIntervalSinceReferenceDate + TimeInterval(minutes * 60)
    return Date(timeIntervalSinceReferenceDate: end.rounded(.down))
  }
}
