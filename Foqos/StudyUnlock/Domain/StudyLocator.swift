import Foundation

enum StudyLocator: Codable, Hashable {
  case pdfPage(Int)
  case epub(href: String, chapter: Int, chapterTitle: String?, progression: Double)

  var label: String {
    switch self {
    case .pdfPage(let page):
      return "p. \(page)"
    case .epub(_, let chapter, let chapterTitle, _):
      guard let chapterTitle, !chapterTitle.isEmpty else { return "ch. \(chapter)" }
      return "ch. \(chapter): \(chapterTitle)"
    }
  }
}
