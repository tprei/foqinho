import Foundation

enum StudyImportError: LocalizedError, Equatable {
  case unsupportedFormat
  case protected
  case noText
  case unreadable

  var errorDescription: String? {
    switch self {
    case .unsupportedFormat: return "Only PDF and EPUB files can be imported."
    case .protected: return "This file is DRM-protected. Use model knowledge instead."
    case .noText: return "No text found (scanned PDF?). Use model knowledge instead."
    case .unreadable: return "Foqos can't read this file."
    }
  }
}
