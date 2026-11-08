import DeviceActivity
import Foundation

enum SoftUnblockGrantScheduler {
  static let activityId = "SoftUnblockGrantTimerActivity"

  struct ActivityIdentifiers: Equatable {
    let profileId: UUID
    let sessionId: String
    let grantId: UUID
  }

  static func scheduleGrant(_ grant: SoftUnblockGrant) throws {
    let schedule = OneShotDeviceActivitySchedule.make(
      endingAt: grant.expiresAt,
      now: Date(),
      calendar: .current
    )
    try DeviceActivityCenter().startMonitoring(activityName(for: grant), during: schedule)
  }

  static func stopAll(sessionId: String? = nil) {
    let center = DeviceActivityCenter()
    let prefix = "\(activityId):"
    let activities = center.activities.filter { activity in
      guard activity.rawValue.hasPrefix(prefix) else { return false }
      guard let sessionId else { return true }
      return identifiers(from: activity)?.sessionId == sessionId
    }

    guard !activities.isEmpty else { return }
    center.stopMonitoring(activities)
  }

  static func identifiers(from activityName: DeviceActivityName) -> ActivityIdentifiers? {
    let components = activityName.rawValue.split(separator: ":", maxSplits: 1)
    guard components.count == 2, components[0] == Substring(activityId) else { return nil }

    let payload = components[1].split(separator: "|", maxSplits: 2)
    guard payload.count == 3,
      let profileId = UUID(uuidString: String(payload[0])),
      let grantId = UUID(uuidString: String(payload[2]))
    else {
      return nil
    }

    return ActivityIdentifiers(
      profileId: profileId,
      sessionId: String(payload[1]),
      grantId: grantId
    )
  }

  private static func activityName(for grant: SoftUnblockGrant) -> DeviceActivityName {
    DeviceActivityName(
      rawValue:
        "\(activityId):\(grant.profileId.uuidString)|\(grant.sessionId)|\(grant.id.uuidString)"
    )
  }
}
