import XCTest

@testable import foqos

final class StudyConversationTests: XCTestCase {
  private let document = StudyDocumentSummary(
    id: UUID(),
    title: "Biologia",
    author: "Ana Lima",
    format: .pdf,
    importedAt: Date(timeIntervalSince1970: 0),
    pageCount: 4,
    passageCount: 4
  )

  private var index: StudyDocumentIndex {
    let passages = (1...4).map { page in
      StudyPassage(
        id: "p\(page).1", locator: .pdfPage(page), text: String(repeating: "texto ", count: 100))
    }
    return StudyDocumentIndex(summary: document, chapters: [], passages: passages)
  }

  private func approvingStep(for conversation: StudyConversation) throws -> StudyStep {
    let request = try XCTUnwrap(conversation.evaluationRequest())
    let evidence = request.passages.prefix(1).map {
      StudyEvidence(passageId: $0.id, locator: $0.locator, concept: "texto")
    }
    let evaluation = StudyEvaluation(
      decision: .pass,
      confidence: 0.9,
      coveredConcepts: ["texto"],
      missingConcepts: [],
      contradictions: [],
      evidence: evidence,
      nextQuestion: nil,
      spokenFeedback: "Muito bem."
    )
    return StudyDecision.next(
      after: evaluation,
      request: request,
      followUpsAsked: conversation.followUpsAsked,
      decidedAt: Date(timeIntervalSince1970: 0)
    )
  }

  func testDocumentModeStartsByAskingThePosition() {
    let conversation = StudyConversation(source: .document(document), language: .portugueseBrazil)

    XCTAssertEqual(conversation.phase, .setup(.position))
    XCTAssertEqual(conversation.mode, .document)
  }

  func testUnclearOrEmptyPositionChangesNothing() {
    var conversation = StudyConversation(source: .document(document), language: .portugueseBrazil)

    XCTAssertEqual(conversation.answerSetup("   ", index: index), .notUnderstood)
    XCTAssertEqual(conversation.answerSetup("li bastante", index: index), .notUnderstood)
    XCTAssertEqual(conversation.answerSetup("páginas 80 a 90", index: index), .notUnderstood)
    XCTAssertEqual(conversation.phase, .setup(.position))
    XCTAssertNil(conversation.subject)
  }

  func testSpokenPositionBecomesTheSubject() {
    var conversation = StudyConversation(source: .document(document), language: .portugueseBrazil)

    XCTAssertEqual(conversation.answerSetup("páginas 2 a 3", index: index), .advanced)

    XCTAssertEqual(conversation.phase, .explaining)
    XCTAssertEqual(
      conversation.subject, StudySubject(title: "Biologia", author: "Ana Lima", position: "pp. 2–3")
    )
  }

  func testEmptyTranscriptsNeverAdvanceOrCountAsAnswers() {
    var conversation = StudyConversation(source: .document(document), language: .portugueseBrazil)
    _ = conversation.answerSetup("página 2", index: index)

    XCTAssertFalse(conversation.recordExplanation(" \n "))
    XCTAssertEqual(conversation.phase, .explaining)
    XCTAssertTrue(conversation.turns.isEmpty)
    XCTAssertNil(conversation.evaluationRequest())
  }

  func testFollowUpConversationKeepsTheFirstPassages() throws {
    var conversation = StudyConversation(source: .document(document), language: .portugueseBrazil)
    _ = conversation.answerSetup("página 2", index: index)
    XCTAssertTrue(conversation.recordExplanation("O texto fala de textos."))
    conversation.freezePassages(index: index)
    let firstPassages = conversation.passages
    XCTAssertFalse(firstPassages.isEmpty)
    XCTAssertEqual(conversation.evaluationRequest()?.followUpsRemaining, 2)

    conversation.apply(.askFollowUp(question: "E depois?", feedback: "Faltou o final."))
    XCTAssertEqual(conversation.phase, .answering(question: "E depois?"))
    XCTAssertEqual(conversation.followUpsAsked, 1)
    XCTAssertFalse(conversation.recordAnswer(""))
    XCTAssertTrue(conversation.recordAnswer("Depois vem a conclusão."))
    conversation.freezePassages(index: index)

    let request = try XCTUnwrap(conversation.evaluationRequest())
    XCTAssertEqual(request.passages, firstPassages)
    XCTAssertEqual(request.followUpsRemaining, 1)
    XCTAssertEqual(
      request.turns,
      [
        .explanation("O texto fala de textos."),
        .followUp(question: "E depois?", answer: "Depois vem a conclusão."),
      ]
    )
  }

  func testRetryAfterAProviderFailureSendsTheSameRequest() {
    var conversation = StudyConversation(source: .document(document), language: .portugueseBrazil)
    _ = conversation.answerSetup("página 2", index: index)
    _ = conversation.recordExplanation("O texto fala de textos.")
    conversation.freezePassages(index: index)

    let first = conversation.evaluationRequest()
    let retried = conversation.evaluationRequest()

    XCTAssertNotNil(first)
    XCTAssertEqual(first, retried)
    XCTAssertEqual(conversation.phase, .evaluating)
  }

  func testApprovalFinishesTheConversation() throws {
    var conversation = StudyConversation(source: .document(document), language: .portugueseBrazil)
    _ = conversation.answerSetup("página 2", index: index)
    _ = conversation.recordExplanation("O texto fala de textos.")
    conversation.freezePassages(index: index)
    let step = try approvingStep(for: conversation)

    conversation.apply(step)

    XCTAssertEqual(conversation.phase, .finished(step))
    guard case .approve = step else { return XCTFail("Expected approval, got \(step)") }
    conversation.apply(.askFollowUp(question: "Mais?", feedback: ""))
    XCTAssertEqual(conversation.phase, .finished(step))
  }

  func testModelKnowledgeAsksTitleAuthorAndPosition() {
    var conversation = StudyConversation(
      source: .modelKnowledge(remembered: nil), language: .portugueseBrazil)

    XCTAssertEqual(conversation.phase, .setup(.title))
    XCTAssertEqual(conversation.answerSetup("Dom Casmurro", index: nil), .advanced)
    XCTAssertEqual(conversation.phase, .setup(.author))
    XCTAssertEqual(conversation.answerSetup("Não sei.", index: nil), .advanced)
    XCTAssertEqual(conversation.phase, .setup(.position))
    XCTAssertEqual(conversation.answerSetup("capítulo 10, o ciúme", index: nil), .advanced)

    XCTAssertEqual(conversation.mode, .modelKnowledge)
    XCTAssertEqual(
      conversation.subject,
      StudySubject(title: "Dom Casmurro", author: nil, position: "capítulo 10, o ciúme")
    )
    XCTAssertTrue(conversation.recordExplanation("Bentinho desconfia de Capitu."))
    XCTAssertEqual(conversation.evaluationRequest()?.passages, [])
  }

  func testRememberedBookSkipsToThePosition() {
    let remembered = StudySubject(title: "Dom Casmurro", author: "Machado de Assis", position: "")
    var conversation = StudyConversation(
      source: .modelKnowledge(remembered: remembered), language: .portugueseBrazil)

    XCTAssertEqual(conversation.phase, .setup(.position))
    _ = conversation.answerSetup("capítulo 12", index: nil)
    XCTAssertEqual(
      conversation.subject,
      StudySubject(title: "Dom Casmurro", author: "Machado de Assis", position: "capítulo 12")
    )
  }
}
