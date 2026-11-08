import XCTest

@testable import foqos

final class StudyVocabularyTests: XCTestCase {
  func testLocatorLabels() {
    XCTAssertEqual(StudyLocator.pdfPage(42).label, "p. 42")
    XCTAssertEqual(
      StudyLocator.epub(href: "c3.xhtml", chapter: 3, chapterTitle: "Método", progression: 0.5)
        .label,
      "ch. 3: Método"
    )
    XCTAssertEqual(
      StudyLocator.epub(href: "c3.xhtml", chapter: 3, chapterTitle: nil, progression: 0).label,
      "ch. 3"
    )
    XCTAssertEqual(
      StudyLocator.epub(href: "c3.xhtml", chapter: 3, chapterTitle: "", progression: 0).label,
      "ch. 3"
    )
  }

  func testGrantCoversOnlyThePauseItStarted() {
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    let grant = StudyUnlockGrant(
      id: UUID(),
      sessionId: "session",
      profileId: UUID(),
      createdAt: createdAt,
      expiresAt: createdAt.addingTimeInterval(900),
      mode: .document,
      coveredConceptCount: 2,
      evidenceLocators: ["p. 41"],
      followUpCount: 0
    )

    XCTAssertTrue(grant.covers(pauseStartedAt: createdAt))
    XCTAssertTrue(grant.covers(pauseStartedAt: createdAt.addingTimeInterval(1)))
    XCTAssertFalse(grant.covers(pauseStartedAt: createdAt.addingTimeInterval(-1)))
    XCTAssertTrue(
      grant.covers(
        pauseStartedAt: createdAt.addingTimeInterval(StudyUnlockGrant.maximumPauseStartDelay - 1)))
    XCTAssertFalse(
      grant.covers(
        pauseStartedAt: createdAt.addingTimeInterval(StudyUnlockGrant.maximumPauseStartDelay)))
    XCTAssertFalse(grant.covers(pauseStartedAt: createdAt.addingTimeInterval(900)))
  }

  func testExpiryEndsOnAWholeSecond() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000.75)

    XCTAssertEqual(
      StudyUnlockRules.expiry(from: now, minutes: 15),
      Date(timeIntervalSinceReferenceDate: 1_900)
    )
  }

  func testMinutesStayWithinTheAllowedRange() {
    XCTAssertEqual(StudyUnlockRules.clampedMinutes(1), 5)
    XCTAssertEqual(StudyUnlockRules.clampedMinutes(15), 15)
    XCTAssertEqual(StudyUnlockRules.clampedMinutes(240), 60)
  }

  func testFoldedTextIgnoresCaseAccentsAndSpacing() {
    XCTAssertEqual(StudyText.folded("  Capítulo\n TRÊS:   Método "), "capitulo tres: metodo")
  }
}
