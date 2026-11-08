import AVFoundation
import Speech

enum StudyVoicePermissions {
  static func requestMicrophone() async throws(StudyListenerError) {
    guard await AVAudioApplication.requestRecordPermission() else { throw .microphoneDenied }
  }

  static func requestSpeechRecognition() async throws(StudyListenerError) {
    let status = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard status == .authorized else { throw .speechRecognitionDenied }
  }
}
