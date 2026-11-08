import AVFoundation
import Speech

@MainActor
final class LegacySpeechTranscriber: StudyTranscriptionBackend {
  private let recognizer: SFSpeechRecognizer
  private let request = SFSpeechAudioBufferRecognitionRequest()
  private let capture = StudyAudioCapture()
  private var task: SFSpeechRecognitionTask?
  private var latestTranscript = ""
  private var outcome: Result<String, StudyListenerError>?
  private var waiter: CheckedContinuation<String, Error>?

  static func route(
    for language: StudyLanguage,
    allowServer: Bool
  ) throws(StudyListenerError) -> StudyListeningRoute {
    let recognizer = try recognizer(for: language)
    if recognizer.supportsOnDeviceRecognition { return .onDevice }
    guard allowServer else { throw .serverRecognitionNeedsConsent }
    return .server
  }

  init(language: StudyLanguage, allowServer: Bool) throws(StudyListenerError) {
    recognizer = try Self.recognizer(for: language)
    let route = try Self.route(for: language, allowServer: allowServer)
    request.requiresOnDeviceRecognition = route == .onDevice
    request.shouldReportPartialResults = true
    request.addsPunctuation = true
  }

  func start() async throws {
    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      let text = result?.bestTranscription.formattedString
      let isFinal = result?.isFinal == true
      let failed = error != nil
      Task { @MainActor in
        self?.handle(text: text, isFinal: isFinal, failed: failed)
      }
    }
    let request = self.request
    try capture.start(
      onBuffer: { request.append($0) },
      onLimitReached: { request.endAudio() }
    )
  }

  func finish() async throws -> String {
    capture.stop()
    request.endAudio()
    if let outcome { return try outcome.get() }
    return try await withCheckedThrowingContinuation { waiter = $0 }
  }

  func cancel() {
    capture.stop()
    task?.cancel()
    resolve(.failure(.nothingHeard))
  }

  private static func recognizer(for language: StudyLanguage) throws(StudyListenerError)
    -> SFSpeechRecognizer
  {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue)),
      recognizer.isAvailable
    else {
      throw .languageUnsupported
    }
    return recognizer
  }

  private func handle(text: String?, isFinal: Bool, failed: Bool) {
    if let text {
      latestTranscript = text
      if isFinal { resolve(.success(latestTranscript)) }
    }
    // The recognizer also reports an error when it heard nothing after endAudio.
    if failed {
      resolve(latestTranscript.isEmpty ? .failure(.nothingHeard) : .success(latestTranscript))
    }
  }

  private func resolve(_ value: Result<String, StudyListenerError>) {
    guard outcome == nil else { return }
    outcome = value
    task = nil
    waiter?.resume(with: value.mapError { $0 as Error })
    waiter = nil
  }
}
