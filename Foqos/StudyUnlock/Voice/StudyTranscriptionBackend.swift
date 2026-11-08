import Foundation

@MainActor
protocol StudyTranscriptionBackend: AnyObject {
  func start() async throws
  func finish() async throws -> String
  func cancel()
}
