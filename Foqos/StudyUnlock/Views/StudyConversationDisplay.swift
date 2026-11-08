import Foundation

enum StudyConversationPhase: Equatable {
  case preparing
  case speaking
  case ready
  case listening(elapsedSeconds: Int)
  case transcribing
  case evaluating

  var isListening: Bool {
    if case .listening = self { return true }
    return false
  }

  var canTalk: Bool {
    self == .ready || isListening
  }

  var label: String {
    switch self {
    case .preparing: return "Getting the microphone ready"
    case .speaking: return "Speaking"
    case .ready: return "Ready to talk"
    case .listening: return "Listening"
    case .transcribing: return "Transcribing"
    case .evaluating: return "Evaluating"
    }
  }

  var symbol: String {
    switch self {
    case .preparing: return "mic"
    case .speaking: return "speaker.wave.2.fill"
    case .ready: return "mic.fill"
    case .listening: return "waveform"
    case .transcribing: return "text.bubble"
    case .evaluating: return "sparkle.magnifyingglass"
    }
  }

  var elapsedLabel: String? {
    guard case .listening(let seconds) = self else { return nil }
    let elapsed = min(max(seconds, 0), 180)
    return String(format: "%01d:%02d", elapsed / 60, elapsed % 60)
  }
}

struct StudyTranscriptLine: Equatable, Identifiable {
  enum Speaker: Equatable {
    case app
    case you
  }

  let id: String
  let speaker: Speaker
  let text: String
}

struct StudyFailureDisplay: Equatable {
  enum Action: Equatable {
    case tryAgain
    case openSettings

    var label: String {
      switch self {
      case .tryAgain: return "Try again"
      case .openSettings: return "Open Settings"
      }
    }
  }

  let message: String
  let action: Action

  init(message: String, action: Action = .tryAgain) {
    self.message = message
    self.action = action
  }
}

enum StudyConsentDisplay: Equatable {
  case provider(host: String, mode: StudyMode)
  case serverSpeech(language: StudyLanguage)
}

struct StudyConversationDisplay: Equatable {
  let source: StudySource
  let positionLabel: String?
  let spokenLine: String
  let phase: StudyConversationPhase
  let followUpNumber: Int
  let transcript: [StudyTranscriptLine]
  let failure: StudyFailureDisplay?
  let consent: StudyConsentDisplay?

  init(
    source: StudySource,
    positionLabel: String? = nil,
    spokenLine: String,
    phase: StudyConversationPhase,
    followUpNumber: Int = 0,
    transcript: [StudyTranscriptLine] = [],
    failure: StudyFailureDisplay? = nil,
    consent: StudyConsentDisplay? = nil
  ) {
    self.source = source
    self.positionLabel = positionLabel
    self.spokenLine = spokenLine
    self.phase = phase
    self.followUpNumber = followUpNumber
    self.transcript = transcript
    self.failure = failure
    self.consent = consent
  }
}
