import Foundation
import PDFKit

struct PDFStudyExtractor {
  static let minimumTextCharacters = 200

  func extract(fileAt url: URL, fallbackTitle: String) throws(StudyImportError) -> StudyExtraction {
    guard let document = PDFDocument(url: url) else { throw .unreadable }
    guard !(document.isEncrypted && document.isLocked) else { throw .protected }

    let blocks = (0..<document.pageCount).map { pageIndex in
      StudyTextBlock(
        origin: .pdfPage(pageIndex + 1),
        text: document.page(at: pageIndex)?.string ?? ""
      )
    }
    let textLength = blocks.reduce(0) { total, block in
      total + block.text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }
    guard textLength >= Self.minimumTextCharacters else { throw .noText }

    let attributes = document.documentAttributes ?? [:]
    return StudyExtraction(
      title: nonEmpty(attributes[PDFDocumentAttribute.titleAttribute]) ?? fallbackTitle,
      author: nonEmpty(attributes[PDFDocumentAttribute.authorAttribute]),
      format: .pdf,
      pageCount: document.pageCount,
      blocks: blocks,
      chapters: chapterMarks(in: document)
    )
  }

  private func chapterMarks(in document: PDFDocument) -> [StudyChapterMark] {
    guard let root = document.outlineRoot else { return [] }
    var marks: [StudyChapterMark] = []
    for topIndex in 0..<root.numberOfChildren {
      guard let top = root.child(at: topIndex) else { continue }
      marks.append(contentsOf: mark(for: top, in: document))
      for childIndex in 0..<top.numberOfChildren {
        guard let child = top.child(at: childIndex) else { continue }
        marks.append(contentsOf: mark(for: child, in: document))
      }
    }
    return marks
  }

  private func mark(for outline: PDFOutline, in document: PDFDocument) -> [StudyChapterMark] {
    guard let title = nonEmpty(outline.label), let page = outline.destination?.page else {
      return []
    }
    return [StudyChapterMark(title: title, start: .pdfPage(document.index(for: page) + 1))]
  }

  private func nonEmpty(_ value: Any?) -> String? {
    guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    else {
      return nil
    }
    return text
  }
}
