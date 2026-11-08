import Foundation

enum StudyUnlockGrantStore {
  static let maximumStoredGrants = 50

  private static let suite = UserDefaults(
    suiteName: "group.dev.ambitionsoftware.foqos"
  )!

  private static let grantsKey = "studyUnlock.grants"

  static func record(_ grant: StudyUnlockGrant) throws {
    let kept = [grant] + grants().filter { $0.id != grant.id }
    try save(Array(kept.prefix(maximumStoredGrants)))
  }

  static func remove(id: UUID) throws {
    try save(grants().filter { $0.id != id })
  }

  // Newest first. Unreadable history starts over, like the other App Group stores.
  static func grants() -> [StudyUnlockGrant] {
    guard let data = suite.data(forKey: grantsKey),
      let grants = try? JSONDecoder().decode([StudyUnlockGrant].self, from: data)
    else {
      return []
    }
    return grants
  }

  static func grant(sessionId: String, coveringPauseStartedAt pauseStart: Date) -> StudyUnlockGrant?
  {
    grants().first { $0.sessionId == sessionId && $0.covers(pauseStartedAt: pauseStart) }
  }

  static func clearAll() {
    suite.removeObject(forKey: grantsKey)
  }

  private static func save(_ grants: [StudyUnlockGrant]) throws {
    suite.set(try JSONEncoder().encode(grants), forKey: grantsKey)
  }
}
