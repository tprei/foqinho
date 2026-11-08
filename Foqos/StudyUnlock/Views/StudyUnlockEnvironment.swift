import Foundation

struct StudyUnlockEnvironment {
  let settings: StudyProviderSettingsStore
  let library: StudyLibrary

  static func live() -> StudyUnlockEnvironment {
    StudyUnlockEnvironment(
      settings: StudyProviderSettingsStore(),
      library: .applicationSupport()
    )
  }
}
