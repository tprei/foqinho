import XCTest

@testable import foqos

final class StudyRetrieverTests: XCTestCase {
  private func summary(_ format: StudyDocumentFormat, passageCount: Int) -> StudyDocumentSummary {
    StudyDocumentSummary(
      id: UUID(),
      title: "Biologia",
      author: nil,
      format: format,
      importedAt: Date(timeIntervalSince1970: 0),
      pageCount: format == .pdf ? 6 : nil,
      passageCount: passageCount
    )
  }

  private func pdfIndex(
    texts: [String],
    chapters: [StudyChapter] = []
  ) -> StudyDocumentIndex {
    let passages = texts.enumerated().map { offset, text in
      StudyPassage(id: "p\(offset + 1).1", locator: .pdfPage(offset + 1), text: text)
    }
    return StudyDocumentIndex(
      summary: summary(.pdf, passageCount: passages.count), chapters: chapters, passages: passages)
  }

  private func filler(_ count: Int) -> String {
    String(repeating: "x", count: count)
  }

  func testPagesWindowCoversThePagesSpoken() throws {
    let index = pdfIndex(texts: ["um", "dois", "três", "quatro"])

    let range = try XCTUnwrap(StudyRetriever.window(for: .pages(first: 2, last: 3), in: index))
    let single = try XCTUnwrap(StudyRetriever.window(for: .pages(first: 4, last: 4), in: index))

    XCTAssertEqual(range.label, "pp. 2–3")
    XCTAssertEqual(range.passages.map(\.id), ["p2.1", "p3.1"])
    XCTAssertEqual(single.label, "p. 4")
  }

  func testPagesOutsideTheDocumentFindNothing() {
    let index = pdfIndex(texts: ["um", "dois"])

    XCTAssertNil(StudyRetriever.window(for: .pages(first: 90, last: 95), in: index))
  }

  func testChapterNumberMatchesTheTitleBeforeTheOrdinal() throws {
    let chapters = [
      StudyChapter(ordinal: 1, title: "Prefácio", firstPassageIndex: 0),
      StudyChapter(ordinal: 2, title: "Capítulo 1: Origem", firstPassageIndex: 1),
      StudyChapter(ordinal: 3, title: "Capítulo 2: Método", firstPassageIndex: 3),
    ]
    let index = pdfIndex(texts: ["a", "b", "c", "d", "e"], chapters: chapters)

    let window = try XCTUnwrap(StudyRetriever.window(for: .chapter(1), in: index))

    XCTAssertEqual(window.passages.map(\.id), ["p2.1", "p3.1"])
    XCTAssertEqual(window.label, "pp. 2–3")
  }

  func testChapterNumberFallsBackToTheOrdinalAndReadsRomanTitles() throws {
    let plain = pdfIndex(
      texts: ["a", "b"],
      chapters: [
        StudyChapter(ordinal: 1, title: "Origem", firstPassageIndex: 0),
        StudyChapter(ordinal: 2, title: "Método", firstPassageIndex: 1),
      ]
    )
    let roman = pdfIndex(
      texts: ["a", "b"],
      chapters: [
        StudyChapter(ordinal: 1, title: "Chapter I", firstPassageIndex: 0),
        StudyChapter(ordinal: 2, title: "Chapter III", firstPassageIndex: 1),
      ]
    )

    XCTAssertEqual(StudyRetriever.window(for: .chapter(2), in: plain)?.passages.map(\.id), ["p2.1"])
    XCTAssertEqual(StudyRetriever.window(for: .chapter(3), in: roman)?.passages.map(\.id), ["p2.1"])
    XCTAssertNil(StudyRetriever.window(for: .chapter(9), in: plain))
  }

  func testChapterTitleMatchesByPhraseOrSharedWords() throws {
    let chapters = [
      StudyChapter(ordinal: 1, title: "A célula", firstPassageIndex: 0),
      StudyChapter(ordinal: 2, title: "Método científico", firstPassageIndex: 1),
    ]
    let index = pdfIndex(texts: ["a", "b"], chapters: chapters)

    XCTAssertEqual(
      StudyRetriever.window(for: .chapterTitle("metodo"), in: index)?.passages.map(\.id), ["p2.1"])
    XCTAssertEqual(
      StudyRetriever.window(for: .chapterTitle("o metodo de pesquisa"), in: index)?.passages
        .map(\.id),
      ["p2.1"]
    )
    XCTAssertNil(StudyRetriever.window(for: .chapterTitle("astronomia"), in: index))
  }

  func testEpubChapterWindowIsLabeledByItsLocator() throws {
    let passages = [
      StudyPassage(
        id: "c1.1",
        locator: .epub(href: "c1.xhtml", chapter: 1, chapterTitle: "Origem", progression: 0),
        text: "a"),
      StudyPassage(
        id: "c2.1",
        locator: .epub(href: "c2.xhtml", chapter: 2, chapterTitle: "Método", progression: 0),
        text: "b"),
    ]
    let index = StudyDocumentIndex(
      summary: summary(.epub, passageCount: 2),
      chapters: [
        StudyChapter(ordinal: 1, title: "Origem", firstPassageIndex: 0),
        StudyChapter(ordinal: 2, title: "Método", firstPassageIndex: 1),
      ],
      passages: passages
    )

    XCTAssertEqual(StudyRetriever.window(for: .chapter(2), in: index)?.label, "ch. 2: Método")
    XCTAssertNil(StudyRetriever.window(for: .pages(first: 1, last: 2), in: index))
  }

  func testSmallWindowWidensForwardThenBackward() {
    let index = pdfIndex(texts: Array(repeating: filler(500), count: 5))
    let window = StudyWindow(label: "p. 3", passages: [index.passages[2]])

    let selected = StudyRetriever.select(from: window, explanation: "", in: index)

    XCTAssertEqual(selected.map(\.id), ["p2.1", "p3.1", "p4.1"])
  }

  func testWindowWithinBudgetIsKeptWhole() {
    let index = pdfIndex(texts: Array(repeating: filler(2_000), count: 4))
    let window = StudyWindow(label: "pp. 1–4", passages: index.passages)

    XCTAssertEqual(
      StudyRetriever.select(from: window, explanation: "", in: index), index.passages)
  }

  func testOverBudgetKeepsTheMostRelevantPassagesInReadingOrder() {
    let texts = [
      "mitocondria energia " + filler(4_980),
      "fotossintese " + filler(4_987),
      "mitocondria " + filler(4_988),
      "nucleo " + filler(4_993),
    ]
    let index = pdfIndex(texts: texts)
    let window = StudyWindow(label: "pp. 1–4", passages: index.passages)

    let selected = StudyRetriever.select(
      from: window, explanation: "A mitocôndria produz energia.", in: index)

    XCTAssertEqual(selected.map(\.id), ["p1.1", "p3.1"])
  }

  func testOverBudgetTiesPreferTheLaterPassage() {
    let index = pdfIndex(texts: Array(repeating: filler(5_000), count: 4))
    let window = StudyWindow(label: "pp. 1–4", passages: index.passages)

    let selected = StudyRetriever.select(from: window, explanation: "nada", in: index)

    XCTAssertEqual(selected.map(\.id), ["p3.1", "p4.1"])
  }
}
