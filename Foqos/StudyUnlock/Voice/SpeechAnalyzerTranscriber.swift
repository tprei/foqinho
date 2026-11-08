import AVFoundation
import Speech

@available(iOS 26.0, *)
@MainActor
final class SpeechAnalyzerTranscriber: StudyTranscriptionBackend {
  private let transcriber: SpeechTranscriber
  private let analyzer: SpeechAnalyzer
  private let capture = StudyAudioCapture()
  private var input: AsyncStream<AnalyzerInput>.Continuation?
  private var results: Task<String, Error>?

  static func supportedLocale(for language: StudyLanguage) async -> Locale? {
    guard SpeechTranscriber.isAvailable else { return nil }
    return await SpeechTranscriber.supportedLocale(
      equivalentTo: Locale(identifier: language.rawValue))
  }

  init(locale: Locale) {
    transcriber = SpeechTranscriber(
      locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    analyzer = SpeechAnalyzer(modules: [transcriber], options: nil)
  }

  func start() async throws {
    if let installation = try await AssetInventory.assetInstallationRequest(supporting: [
      transcriber
    ]) {
      try await installation.downloadAndInstall()
    }
    guard
      let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber])
    else {
      throw StudyListenerError.languageUnsupported
    }

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    input = continuation
    results = Task { [transcriber] in
      var finalText: [String] = []
      for try await result in transcriber.results where result.isFinal {
        finalText.append(String(result.text.characters))
      }
      return finalText.joined(separator: " ")
    }
    try await analyzer.start(inputSequence: stream)

    let converter = AVAudioConverter(from: capture.inputFormat, to: analyzerFormat)
    try capture.start(
      onBuffer: { buffer in
        guard let converted = Self.convert(buffer, with: converter, to: analyzerFormat) else {
          return
        }
        continuation.yield(AnalyzerInput(buffer: converted))
      },
      onLimitReached: { continuation.finish() }
    )
  }

  func finish() async throws -> String {
    capture.stop()
    input?.finish()
    input = nil
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    guard let results else { return "" }
    return try await results.value
  }

  func cancel() {
    capture.stop()
    input?.finish()
    input = nil
    results?.cancel()
    results = nil
    let analyzer = analyzer
    Task { await analyzer.cancelAndFinishNow() }
  }

  // Runs on the audio render thread, from the capture tap.
  nonisolated private static func convert(
    _ buffer: AVAudioPCMBuffer,
    with converter: AVAudioConverter?,
    to format: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    guard buffer.format != format else { return buffer }
    guard let converter else { return nil }

    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      return nil
    }

    var delivered = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
      guard !delivered else {
        inputStatus.pointee = .noDataNow
        return nil
      }
      delivered = true
      inputStatus.pointee = .haveData
      return buffer
    }
    guard status != .error, conversionError == nil else { return nil }
    return output
  }
}
