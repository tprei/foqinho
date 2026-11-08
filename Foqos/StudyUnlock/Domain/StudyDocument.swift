import Foundation

struct StudyPassage: Codable, Hashable, Identifiable {
  let id: String
  let locator: StudyLocator
  let text: String
}

struct StudyChapter: Codable, Hashable {
  let ordinal: Int
  let title: String
  let firstPassageIndex: Int
}

enum StudyDocumentFormat: String, Codable {
  case pdf
  case epub
}

struct StudyDocumentSummary: Codable, Hashable, Identifiable {
  let id: UUID
  let title: String
  let author: String?
  let format: StudyDocumentFormat
  let importedAt: Date
  let pageCount: Int?
  let passageCount: Int
}

struct StudyDocumentIndex: Codable, Equatable {
  let summary: StudyDocumentSummary
  let chapters: [StudyChapter]
  let passages: [StudyPassage]
}

struct StudyTextBlock: Equatable {
  enum Origin: Equatable {
    case pdfPage(Int)
    case epubResource(href: String)
  }

  let origin: Origin
  let text: String
}

struct StudyChapterMark: Equatable {
  enum Start: Equatable {
    case pdfPage(Int)
    case epubResource(href: String)
  }

  let title: String
  let start: Start
}

struct StudyExtraction: Equatable {
  let title: String
  let author: String?
  let format: StudyDocumentFormat
  let pageCount: Int?
  let blocks: [StudyTextBlock]
  let chapters: [StudyChapterMark]
}
