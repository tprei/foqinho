import AVFoundation

@MainActor
final class StudySpeechSynthesizer: NSObject, StudySpeaker, AVSpeechSynthesizerDelegate {
  private struct PendingSpeech {
    let utterance: AVSpeechUtterance
    let continuation: CheckedContinuation<Void, Never>
  }

  private let synthesizer = AVSpeechSynthesizer()
  private var pendingSpeech: PendingSpeech?

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(_ text: String, language: StudyLanguage) async {
    stopSpeaking()
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: language.rawValue)
    await withCheckedContinuation { continuation in
      pendingSpeech = PendingSpeech(utterance: utterance, continuation: continuation)
      synthesizer.speak(utterance)
    }
  }

  func stopSpeaking() {
    let pending = pendingSpeech
    pendingSpeech = nil
    synthesizer.stopSpeaking(at: .immediate)
    pending?.continuation.resume()
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in self.finish(utterance) }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in self.finish(utterance) }
  }

  private func finish(_ utterance: AVSpeechUtterance) {
    guard let pending = pendingSpeech, pending.utterance === utterance else { return }
    pendingSpeech = nil
    pending.continuation.resume()
  }
}
