import XCTest

@testable import foqos

final class StudyPositionParserTests: XCTestCase {
  private func portuguese(_ transcript: String) -> StudyPosition? {
    StudyPositionParser.parse(transcript, language: .portugueseBrazil)
  }

  private func english(_ transcript: String) -> StudyPosition? {
    StudyPositionParser.parse(transcript, language: .englishUS)
  }

  func testPortuguesePageRanges() {
    XCTAssertEqual(portuguese("Estou nas páginas 40 a 52."), .pages(first: 40, last: 52))
    XCTAssertEqual(portuguese("li da página 40 até a 52"), .pages(first: 40, last: 52))
    XCTAssertEqual(portuguese("Página 12"), .pages(first: 12, last: 12))
    XCTAssertEqual(portuguese("páginas 52 a 40"), .pages(first: 40, last: 52))
    XCTAssertEqual(portuguese("páginas 40-45"), .pages(first: 40, last: 45))
    XCTAssertEqual(
      portuguese("li as páginas vinte e três e vinte e quatro"),
      .pages(first: 23, last: 24)
    )
  }

  func testPortugueseChapters() {
    XCTAssertEqual(portuguese("capítulo 3"), .chapter(3))
    XCTAssertEqual(portuguese("Estou no capítulo três"), .chapter(3))
    XCTAssertEqual(portuguese("capítulo IV"), .chapter(4))
    XCTAssertEqual(portuguese("capítulo vinte e um"), .chapter(21))
    XCTAssertEqual(
      portuguese("o capítulo sobre a Revolução Francesa"),
      .chapterTitle("revolucao francesa")
    )
  }

  func testEnglishPositions() {
    XCTAssertEqual(english("pages 40 to 52"), .pages(first: 40, last: 52))
    XCTAssertEqual(english("page forty-two"), .pages(first: 42, last: 42))
    XCTAssertEqual(english("chapter twenty three"), .chapter(23))
    XCTAssertEqual(english("Chapter III"), .chapter(3))
    XCTAssertEqual(english("the chapter called The Long Night"), .chapterTitle("long night"))
  }

  func testPagesWinOverAChapterInTheSameAnswer() {
    XCTAssertEqual(portuguese("capítulo 3, páginas 40 a 45"), .pages(first: 40, last: 45))
  }

  func testAnswersWithoutAPositionAreNotUnderstood() {
    XCTAssertNil(portuguese("eu li bastante hoje"))
    XCTAssertNil(portuguese("página"))
    XCTAssertNil(portuguese("capítulo iiii"))
    XCTAssertNil(portuguese("40 a 52"))
    XCTAssertNil(english("chapter called"))
  }
}
