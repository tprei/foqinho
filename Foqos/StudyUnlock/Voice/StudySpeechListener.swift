import Foundation

@MainActor
final class StudySpeechListener: StudyListener {
  private var backend: StudyTranscriptionBackend?

  func prepare(language: StudyLanguage, allowServer: Bool) async throws -> StudyListeningRoute {
    try await StudyVoicePermissions.requestMicrophone()
    if #available(iOS 26.0, *),
      await SpeechAnalyzerTranscriber.supportedLocale(for: language) != nil
    {
      return .onDevice
    }
    try await StudyVoicePermissions.requestSpeechRecognition()
    return try LegacySpeechTranscriber.route(for: language, allowServer: allowServer)
  }

  func startListening(language: StudyLanguage, allowServer: Bool) async throws {
    cancelListening()
    do {
      try StudyAudioSession.activate()
    } catch {
      throw StudyListenerError.audioUnavailable
    }
    let backend = try await makeBackend(language: language, allowServer: allowServer)
    self.backend = backend
    do {
      try await backend.start()
    } catch {
      backend.cancel()
      if self.backend === backend { self.backend = nil }
      throw Self.listenerError(from: error)
    }
  }

  func finishListening() async throws -> String {
    guard let backend else { throw StudyListenerError.nothingHeard }
    self.backend = nil

    let transcript: String
    do {
      transcript = try await backend.finish()
    } catch {
      throw Self.listenerError(from: error)
    }
    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw StudyListenerError.nothingHeard }
    return trimmed
  }

  func cancelListening() {
    backend?.cancel()
    backend = nil
  }

  private func makeBackend(
    language: StudyLanguage,
    allowServer: Bool
  ) async throws -> StudyTranscriptionBackend {
    if #available(iOS 26.0, *),
      let locale = await SpeechAnalyzerTranscriber.supportedLocale(for: language)
    {
      return SpeechAnalyzerTranscriber(locale: locale)
    }
    return try LegacySpeechTranscriber(language: language, allowServer: allowServer)
  }

  private static func listenerError(from error: Error) -> StudyListenerError {
    error as? StudyListenerError ?? .recognitionFailed
  }
}
