import Foundation

enum StudyIndexer {
  static let targetCharacters = 2_400
  static let maximumCharacters = 3_200
  static let overlapCharacters = 200

  static func index(_ extraction: StudyExtraction, id: UUID, importedAt: Date) -> StudyDocumentIndex
  {
    let marks = keptChapterMarks(extraction)

    var passages: [StudyPassage] = []
    var passageBlockOrders: [Int] = []
    for (blockOrder, block) in extraction.blocks.enumerated() {
      let text = normalized(block.text)
      for (part, chunk) in chunks(of: text).enumerated() {
        let id = passageId(origin: block.origin, blockOrder: blockOrder, part: part + 1)
        let locator = locator(
          origin: block.origin, blockOrder: blockOrder, chunk: chunk, textLength: text.count,
          marks: marks)
        passages.append(StudyPassage(id: id, locator: locator, text: chunk.text))
        passageBlockOrders.append(blockOrder)
      }
    }

    let chapters = marks.enumerated().compactMap { offset, mark -> StudyChapter? in
      guard let first = passageBlockOrders.firstIndex(where: { $0 >= mark.blockOrder }) else {
        return nil
      }
      return StudyChapter(ordinal: offset + 1, title: mark.title, firstPassageIndex: first)
    }

    let summary = StudyDocumentSummary(
      id: id,
      title: extraction.title,
      author: extraction.author,
      format: extraction.format,
      importedAt: importedAt,
      pageCount: extraction.pageCount,
      passageCount: passages.count
    )
    return StudyDocumentIndex(summary: summary, chapters: chapters, passages: passages)
  }

  private struct KeptMark {
    let title: String
    let blockOrder: Int
  }

  private struct Chunk {
    let start: Int
    let text: String
  }

  private static func passageId(origin: StudyTextBlock.Origin, blockOrder: Int, part: Int) -> String
  {
    switch origin {
    case .pdfPage(let page): return "p\(page).\(part)"
    case .epubResource: return "c\(blockOrder + 1).\(part)"
    }
  }

  private static func locator(
    origin: StudyTextBlock.Origin,
    blockOrder: Int,
    chunk: Chunk,
    textLength: Int,
    marks: [KeptMark]
  ) -> StudyLocator {
    switch origin {
    case .pdfPage(let page):
      return .pdfPage(page)
    case .epubResource(let href):
      let chapterOffset = marks.lastIndex { $0.blockOrder <= blockOrder }
      return .epub(
        href: href,
        chapter: (chapterOffset ?? 0) + 1,
        chapterTitle: chapterOffset.map { marks[$0].title },
        progression: Double(chunk.start) / Double(max(textLength, 1))
      )
    }
  }

  private static func keptChapterMarks(_ extraction: StudyExtraction) -> [KeptMark] {
    extraction.chapters.compactMap { mark in
      let blockOrder = extraction.blocks.firstIndex { block in
        switch (mark.start, block.origin) {
        case (.pdfPage(let page), .pdfPage(let blockPage)):
          return page >= 1 && blockPage >= page
        case (.epubResource(let href), .epubResource(let blockHref)):
          return href == blockHref
        case (.pdfPage, .epubResource), (.epubResource, .pdfPage):
          return false
        }
      }
      return blockOrder.map { KeptMark(title: mark.title, blockOrder: $0) }
    }
  }

  private static func normalized(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .components(separatedBy: "\n\n")
      .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
  }

  private static func chunks(of text: String) -> [Chunk] {
    let characters = Array(text)
    var chunks: [Chunk] = []
    var start = 0
    while start < characters.count {
      guard characters.count - start > maximumCharacters else {
        chunks.append(Chunk(start: start, text: String(characters[start...])))
        break
      }
      let end = splitPoint(in: characters, from: start)
      let chunkText = String(characters[start..<end]).trimmingCharacters(
        in: .whitespacesAndNewlines)
      chunks.append(Chunk(start: start, text: chunkText))
      start = nextStart(in: characters, after: end, previousStart: start)
    }
    return chunks
  }

  private static func splitPoint(in characters: [Character], from start: Int) -> Int {
    let earliest = start + targetCharacters / 2
    let limit = start + maximumCharacters
    let breaks: [(Int) -> Bool] = [
      { characters[$0] == "\n" && characters[$0 - 1] == "\n" },
      { ".!?".contains(characters[$0 - 1]) && characters[$0].isWhitespace },
      { characters[$0].isWhitespace },
    ]
    for isBreak in breaks {
      if let split = stride(from: limit - 1, through: earliest, by: -1).first(where: isBreak) {
        return split
      }
    }
    return limit
  }

  private static func nextStart(in characters: [Character], after end: Int, previousStart: Int)
    -> Int
  {
    var next = max(end - overlapCharacters, previousStart + 1)
    while next < end, !characters[next - 1].isWhitespace {
      next += 1
    }
    while next < characters.count, characters[next].isWhitespace {
      next += 1
    }
    return next
  }
}
