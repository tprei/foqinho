import Foundation

enum StudyFailureText {
  static func message(for failure: StudySessionModel.Failure) -> String {
    switch failure {
    case .providerNotConfigured:
      return "Set up a model in Settings → Study unlock."
    case .missingCredential:
      return "Add the API key for this endpoint in Settings → Study unlock."
    case .needsProviderConsent(let host):
      return "Allow sending this conversation to \(host)."
    case .needsServerSpeechConsent:
      return "Allow Apple's servers to transcribe your speech."
    case .consentNotSaved:
      return "Couldn't save your choice. Nothing was sent."
    case .microphoneDenied:
      return "Microphone access is off. Turn it on in iOS Settings."
    case .speechRecognitionDenied:
      return "Speech recognition is off. Turn it on in iOS Settings."
    case .languageUnavailable:
      return "Speech recognition isn't available for this language on this iPhone."
    case .nothingHeard:
      return "Didn't catch that."
    case .positionNotUnderstood:
      return "Couldn't find that part of the file. Say the pages or the chapter."
    case .evaluationFailed(let error):
      return message(for: error)
    case .invalidEvaluation:
      return "The model's evaluation didn't pass validation. Nothing was unlocked."
    case .documentUnavailable:
      return "This file's index couldn't be read. Import it again."
    case .unlockFailed(let reason):
      return "You passed, but blocking couldn't pause. \(reason)"
    case .settingsChanged:
      return "Settings updated. Tap Try again."
    case .audioUnavailable:
      return "Another app is using audio, like a call. When it's over, tap Try again."
    }
  }

  static func opensSettings(_ failure: StudySessionModel.Failure) -> Bool {
    switch failure {
    case .providerNotConfigured, .missingCredential, .languageUnavailable, .documentUnavailable,
      .microphoneDenied, .speechRecognitionDenied:
      return true
    case .evaluationFailed(.some(.httpStatus(401))), .evaluationFailed(.some(.httpStatus(403))):
      return true
    default:
      return false
    }
  }

  private static func message(for error: StudyProviderError?) -> String {
    switch error {
    case .some(.offline):
      return "You're offline. Nothing was unlocked."
    case .some(.timedOut):
      return "The model took too long. Nothing was unlocked."
    case .some(.httpStatus(401)), .some(.httpStatus(403)):
      return "The endpoint rejected the API key."
    case .some(.httpStatus(429)):
      return "The endpoint is limiting requests. Try again in a moment."
    case .some(.httpStatus(let code)):
      return "The endpoint answered with error \(code). Nothing was unlocked."
    case .some(.refused):
      return "The model refused to evaluate this. Nothing was unlocked."
    case .some(.notConfigured), .some(.missingCredential):
      return "Check the model settings."
    case .some(.malformedResponse), nil:
      return "The model's reply wasn't valid. Nothing was unlocked."
    }
  }
}
