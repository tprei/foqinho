import DeviceActivity
import Foundation

enum OneShotDeviceActivitySchedule {
  static let minimumLeadTime: TimeInterval = 60
  // DeviceActivity rejects intervals shorter than 15 minutes; one more keeps the
  // whole-second rounding of date components from landing exactly on the limit.
  static let minimumInterval: TimeInterval = 16 * 60

  // The interval starts in the past so monitoring begins at once, and it ends at the exact
  // end, on the next day if needed. It is never shorter than the minimum, even just after
  // midnight, and never much longer than the time it covers.
  static func make(endingAt end: Date, now: Date, calendar: Calendar) -> DeviceActivitySchedule {
    let intervalEnd = max(end, now.addingTimeInterval(minimumLeadTime))
    let intervalStart = min(
      now.addingTimeInterval(-minimumLeadTime), intervalEnd.addingTimeInterval(-minimumInterval))
    let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
    return DeviceActivitySchedule(
      intervalStart: calendar.dateComponents(components, from: intervalStart),
      intervalEnd: calendar.dateComponents(components, from: intervalEnd),
      repeats: false
    )
  }
}
