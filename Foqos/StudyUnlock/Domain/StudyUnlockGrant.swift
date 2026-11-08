import Foundation

struct StudyUnlockGrant: Codable, Equatable, Identifiable {
  // The pause timer starts its interval as soon as it's scheduled, so a pause that starts
  // later than this belongs to something else.
  static let maximumPauseStartDelay: TimeInterval = 300

  let id: UUID
  let sessionId: String
  let profileId: UUID
  let createdAt: Date
  let expiresAt: Date
  let mode: StudyMode
  let coveredConceptCount: Int
  let evidenceLocators: [String]
  let followUpCount: Int

  func covers(pauseStartedAt pauseStart: Date) -> Bool {
    let latestStart = min(expiresAt, createdAt.addingTimeInterval(Self.maximumPauseStartDelay))
    return createdAt <= pauseStart && pauseStart < latestStart
  }
}
