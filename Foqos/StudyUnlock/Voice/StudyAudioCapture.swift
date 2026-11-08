import AVFoundation

// Buffers go straight to the recognizer and are never kept or written to disk.
@MainActor
final class StudyAudioCapture {
  static let maximumDuration: Duration = .seconds(180)

  private let engine = AVAudioEngine()
  private var limitTask: Task<Void, Never>?

  var inputFormat: AVAudioFormat {
    engine.inputNode.outputFormat(forBus: 0)
  }

  func start(
    onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
    onLimitReached: @escaping () -> Void
  ) throws {
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    // An inactive or interrupted audio session reports an empty format, and installing a tap
    // with it raises an Objective-C exception.
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw StudyListenerError.audioUnavailable
    }
    input.installTap(onBus: 0, bufferSize: 4_096, format: format, block: Self.tap(onBuffer))
    engine.prepare()
    try engine.start()

    limitTask = Task { [weak self] in
      do {
        try await Task.sleep(for: Self.maximumDuration)
      } catch {
        return
      }
      self?.stop()
      onLimitReached()
    }
  }

  func stop() {
    limitTask?.cancel()
    limitTask = nil
    engine.inputNode.removeTap(onBus: 0)
    if engine.isRunning { engine.stop() }
  }

  // Built outside the main actor: the tap runs on the audio render thread.
  nonisolated private static func tap(
    _ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
  ) -> AVAudioNodeTapBlock {
    { buffer, _ in onBuffer(buffer) }
  }
}
