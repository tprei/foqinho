import XCTest

@testable import foqos

final class StudyIndexerTests: XCTestCase {
  private let id = UUID()
  private let importedAt = Date(timeIntervalSince1970: 1_800_000_000)

  private func sentences(_ count: Int, word: String = "texto") -> String {
    (1...count).map { "Frase \($0) sobre \(word) e mais \(word)." }.joined(separator: " ")
  }

  private func pdf(_ pages: [String], chapters: [StudyChapterMark] = []) -> StudyDocumentIndex {
    let extraction = StudyExtraction(
      title: "Biologia",
      author: "Ana Lima",
      format: .pdf,
      pageCount: pages.count,
      blocks: pages.enumerated().map {
        StudyTextBlock(origin: .pdfPage($0.offset + 1), text: $0.element)
      },
      chapters: chapters
    )
    return StudyIndexer.index(extraction, id: id, importedAt: importedAt)
  }

  func testPdfPassagesFollowPagesAndSkipEmptyOnes() {
    let index = pdf(["Primeira   página\n com texto.", " \n\n ", "Terceira página."])

    XCTAssertEqual(index.passages.map(\.id), ["p1.1", "p3.1"])
    XCTAssertEqual(index.passages.map(\.locator), [.pdfPage(1), .pdfPage(3)])
    XCTAssertEqual(index.passages.first?.text, "Primeira página com texto.")
    XCTAssertEqual(index.summary.id, id)
    XCTAssertEqual(index.summary.importedAt, importedAt)
    XCTAssertEqual(index.summary.pageCount, 3)
    XCTAssertEqual(index.summary.passageCount, 2)
  }

  func testLongPageSplitsAtSentencesWithOverlap() throws {
    let index = pdf([sentences(250)])
    let parts = index.passages

    XCTAssertGreaterThan(parts.count, 2)
    XCTAssertEqual(parts.map(\.id), (1...parts.count).map { "p1.\($0)" })
    for part in parts {
      XCTAssertLessThanOrEqual(part.text.count, StudyIndexer.maximumCharacters)
      XCTAssertEqual(part.locator, .pdfPage(1))
    }
    for (previous, next) in zip(parts, parts.dropFirst()) {
      XCTAssertTrue(previous.text.hasSuffix("."), "split mid-sentence: \(previous.text.suffix(20))")
      let opening = String(next.text.prefix(30))
      XCTAssertTrue(previous.text.contains(opening), "no overlap before \(opening)")
    }
  }

  func testParagraphBreaksArePreferredAndKept() throws {
    let firstParagraph = sentences(40)
    let page = firstParagraph + "\n\n" + sentences(60, word: "método")

    let parts = pdf([page]).passages

    XCTAssertEqual(parts.first?.text, firstParagraph)
    XCTAssertGreaterThan(firstParagraph.count, StudyIndexer.targetCharacters / 2)
  }

  func testPdfChaptersMapToTheirFirstPassageAndDropMissingPages() {
    let chapters = [
      StudyChapterMark(title: "Introdução", start: .pdfPage(1)),
      StudyChapterMark(title: "Capítulo 2", start: .pdfPage(2)),
      StudyChapterMark(title: "Apêndice", start: .pdfPage(99)),
    ]

    let index = pdf(["Um.", "", "Três."], chapters: chapters)

    XCTAssertEqual(
      index.chapters,
      [
        StudyChapter(ordinal: 1, title: "Introdução", firstPassageIndex: 0),
        StudyChapter(ordinal: 2, title: "Capítulo 2", firstPassageIndex: 1),
      ]
    )
  }

  func testEpubPassagesCarryChapterAndProgression() throws {
    let extraction = StudyExtraction(
      title: "Livro",
      author: nil,
      format: .epub,
      pageCount: nil,
      blocks: [
        StudyTextBlock(origin: .epubResource(href: "cover.xhtml"), text: "Capa"),
        StudyTextBlock(origin: .epubResource(href: "ch1.xhtml"), text: sentences(200)),
        StudyTextBlock(origin: .epubResource(href: "ch2.xhtml"), text: "O método tem passos."),
      ],
      chapters: [
        StudyChapterMark(title: "Capítulo 1: Origem", start: .epubResource(href: "ch1.xhtml")),
        StudyChapterMark(title: "Capítulo 2: Método", start: .epubResource(href: "ch2.xhtml")),
        StudyChapterMark(title: "Notas", start: .epubResource(href: "missing.xhtml")),
      ]
    )

    let index = StudyIndexer.index(extraction, id: id, importedAt: importedAt)

    let cover = try XCTUnwrap(index.passages.first)
    XCTAssertEqual(cover.id, "c1.1")
    XCTAssertEqual(
      cover.locator, .epub(href: "cover.xhtml", chapter: 1, chapterTitle: nil, progression: 0))

    let chapterOne = index.passages.filter { $0.id.hasPrefix("c2.") }
    XCTAssertGreaterThan(chapterOne.count, 1)
    guard case .epub(let href, let chapter, let title, let progression) = chapterOne[1].locator
    else {
      return XCTFail("Expected an EPUB locator")
    }
    XCTAssertEqual(href, "ch1.xhtml")
    XCTAssertEqual(chapter, 1)
    XCTAssertEqual(title, "Capítulo 1: Origem")
    XCTAssertGreaterThan(progression, 0)
    XCTAssertLessThan(progression, 1)

    XCTAssertEqual(
      index.passages.last?.locator,
      .epub(href: "ch2.xhtml", chapter: 2, chapterTitle: "Capítulo 2: Método", progression: 0)
    )
    XCTAssertEqual(index.chapters.map(\.title), ["Capítulo 1: Origem", "Capítulo 2: Método"])
    XCTAssertEqual(index.chapters.map(\.firstPassageIndex), [1, index.passages.count - 1])
  }
}
