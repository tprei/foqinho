import AVFoundation

enum StudyAudioSession {
  static func activate() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    try session.setActive(true)
  }

  static func deactivate() throws {
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    } catch let error as NSError where error.code == AVAudioSession.ErrorCode.isBusy.rawValue {
      // Apple documents isBusy here as: the running audio was stopped and the session is
      // inactive anyway. Speech that was still stopping is the usual cause.
      return
    }
  }
}
