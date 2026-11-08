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

  var isModelConfigured: Bool {
    settings.load().configuration != nil
  }

  @MainActor
  func sessionDependencies(
    unlock: @escaping (StudyApproval) throws -> StudyUnlockGrant
  ) -> StudySessionDependencies {
    let settings = settings
    let library = library
    return StudySessionDependencies(
      speaker: StudySpeechSynthesizer(),
      listener: StudySpeechListener(),
      currentLanguage: { settings.load().language },
      loadIndex: { try library.index(for: $0) },
      rememberSubject: { library.rememberedSubject = $0 },
      makeProvider: { try StudyProviderFactory.make(settings: settings) },
      hasProviderConsent: { settings.hasConsent(host: $0) },
      recordProviderConsent: { try settings.recordConsent(host: $0) },
      allowsServerSpeech: { settings.load().allowsServerSpeech },
      recordServerSpeechConsent: {
        var current = settings.load()
        current.allowsServerSpeech = true
        try settings.save(current)
      },
      unlock: unlock,
      now: Date.init
    )
  }
}
