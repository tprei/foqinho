import Foundation

enum StudyUnlockError: LocalizedError, Equatable {
  case noActiveSession
  case sessionChanged
  case unsupportedStrategy(profileName: String)
  case disabled(profileName: String)
  case pauseActive
  case breakActive
  case recordingFailed
  case schedulingFailed(reason: String)

  var errorDescription: String? {
    switch self {
    case .noActiveSession:
      return "No session is running, so there's nothing to unlock."
    case .sessionChanged:
      return "The session changed while you were talking. Nothing was unlocked."
    case .unsupportedStrategy(let profileName):
      return "\(profileName) uses Temporary Access, which doesn't support study unlock."
    case .disabled(let profileName):
      return "Study unlock is off for \(profileName)."
    case .pauseActive:
      return "Blocking is already paused."
    case .breakActive:
      return "A break is already running."
    case .recordingFailed:
      return "The unlock couldn't be recorded. Nothing was unlocked."
    case .schedulingFailed(let reason):
      return "The pause couldn't be scheduled: \(reason)"
    }
  }
}
