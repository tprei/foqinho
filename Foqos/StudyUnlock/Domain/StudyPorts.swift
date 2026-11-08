import Foundation

@MainActor
protocol StudySpeaker: AnyObject {
  func speak(_ text: String, language: StudyLanguage) async
  func stopSpeaking()
}

enum StudyListeningRoute: Equatable {
  case onDevice
  case server
}

@MainActor
protocol StudyListener: AnyObject {
  func prepare(language: StudyLanguage, allowServer: Bool) async throws -> StudyListeningRoute
  func startListening(language: StudyLanguage, allowServer: Bool) async throws
  // Stops capture and returns the final transcript; audio buffers are released before returning.
  func finishListening() async throws -> String
  func cancelListening()
}

enum StudyListenerError: Error, Equatable {
  case microphoneDenied
  case speechRecognitionDenied
  case languageUnsupported
  case serverRecognitionNeedsConsent
  case nothingHeard
  case recognitionFailed
  case audioUnavailable
}

protocol StudyModelProvider {
  // The host the conversation is sent to; consent is recorded per host.
  var host: String { get }
  func evaluate(_ request: StudyEvaluationRequest) async throws -> StudyEvaluationPayload
}

enum StudyProviderError: Error, Equatable {
  case notConfigured
  case missingCredential
  case timedOut
  case offline
  case httpStatus(Int)
  case refused
  case malformedResponse
}
