import XCTest

@testable import foqos

final class StudyEvaluationValidatorTests: XCTestCase {
  private typealias Fixtures = StudyDomainFixtures
  private typealias Evidence = StudyEvaluationPayload.Evidence

  private func validate(
    _ payload: StudyEvaluationPayload,
    _ request: StudyEvaluationRequest = Fixtures.request()
  ) -> Result<StudyEvaluation, StudyEvaluationProblem> {
    StudyEvaluationValidator.validate(payload, for: request)
  }

  private func problem(
    _ payload: StudyEvaluationPayload,
    _ request: StudyEvaluationRequest = Fixtures.request()
  ) -> StudyEvaluationProblem? {
    guard case .failure(let problem) = validate(payload, request) else { return nil }
    return problem
  }

  func testValidPassKeepsThePassageLocatorAndTrimsText() throws {
    let payload = Fixtures.payload(
      coveredConcepts: ["  ATP vem da mitocôndria  "],
      evidence: [Evidence(chunkId: " p41.1 ", locator: "p. 41", concept: " ATP ")],
      nextQuestion: "   ",
      spokenFeedback: " Muito bem. "
    )

    let evaluation = try validate(payload).get()

    XCTAssertEqual(evaluation.decision, .pass)
    XCTAssertEqual(evaluation.coveredConcepts, ["ATP vem da mitocôndria"])
    XCTAssertEqual(
      evaluation.evidence,
      [StudyEvidence(passageId: "p41.1", locator: .pdfPage(41), concept: "ATP")]
    )
    XCTAssertNil(evaluation.nextQuestion)
    XCTAssertEqual(evaluation.spokenFeedback, "Muito bem.")
  }

  func testUnknownDecisionIsRejectedBeforeOtherProblems() {
    let payload = Fixtures.payload(decision: "approve", basis: "model_knowledge")

    XCTAssertEqual(problem(payload), .unknownDecision)
  }

  func testBasisMustMatchTheRequestMode() {
    XCTAssertEqual(problem(Fixtures.payload(basis: "model_knowledge")), .basisMismatch)
    XCTAssertEqual(
      problem(
        Fixtures.payload(basis: "document", evidence: []), Fixtures.request(mode: .modelKnowledge)),
      .basisMismatch
    )
  }

  func testConfidenceMustBeWithinZeroAndOne() {
    XCTAssertEqual(problem(Fixtures.payload(confidence: 1.01)), .confidenceOutOfRange)
    XCTAssertEqual(problem(Fixtures.payload(confidence: -0.01)), .confidenceOutOfRange)
    XCTAssertEqual(problem(Fixtures.payload(confidence: .nan)), .confidenceOutOfRange)
    XCTAssertNotNil(try? validate(Fixtures.payload(confidence: 0)).get())
    XCTAssertNotNil(try? validate(Fixtures.payload(confidence: 1)).get())
  }

  func testConceptListsAreBoundedInCountAndLength() {
    let eleven = (1...11).map { "conceito \($0)" }
    XCTAssertEqual(
      problem(Fixtures.payload(coveredConcepts: eleven)), .tooManyItems("coveredConcepts"))
    XCTAssertEqual(
      problem(Fixtures.payload(missingConcepts: [" \n "])), .emptyField("missingConcepts"))
    XCTAssertEqual(
      problem(Fixtures.payload(contradictions: [String(repeating: "a", count: 161)])),
      .fieldTooLong("contradictions")
    )
    let tooMuchEvidence = Array(
      repeating: Evidence(chunkId: "p41.1", locator: "p. 41", concept: "ATP"), count: 11)
    XCTAssertEqual(problem(Fixtures.payload(evidence: tooMuchEvidence)), .tooManyItems("evidence"))
  }

  func testSpokenFeedbackIsRequiredAndBounded() {
    XCTAssertEqual(problem(Fixtures.payload(spokenFeedback: "  ")), .emptyField("spokenFeedback"))
    XCTAssertEqual(
      problem(Fixtures.payload(spokenFeedback: String(repeating: "a", count: 501))),
      .fieldTooLong("spokenFeedback")
    )
  }

  func testFollowUpNeedsAQuestion() {
    XCTAssertEqual(
      problem(Fixtures.payload(decision: "follow_up", nextQuestion: "  ")),
      .missingNextQuestion
    )
    XCTAssertEqual(
      problem(
        Fixtures.payload(decision: "follow_up", nextQuestion: String(repeating: "a", count: 301))),
      .fieldTooLong("nextQuestion")
    )
    let evaluation = try? validate(
      Fixtures.payload(decision: "follow_up", nextQuestion: " Por que a célula precisa de ATP? ")
    ).get()
    XCTAssertEqual(evaluation?.decision, .followUp)
    XCTAssertEqual(evaluation?.nextQuestion, "Por que a célula precisa de ATP?")
  }

  func testModelKnowledgeModeRejectsAnyEvidence() {
    let payload = Fixtures.payload(basis: "model_knowledge")

    XCTAssertEqual(
      problem(payload, Fixtures.request(mode: .modelKnowledge)), .evidenceWithoutDocument)
    XCTAssertNotNil(
      try? validate(
        Fixtures.payload(basis: "model_knowledge", evidence: []),
        Fixtures.request(mode: .modelKnowledge)
      ).get()
    )
  }

  func testEvidenceMustCiteAPassageThatWasSent() {
    let payload = Fixtures.payload(
      evidence: [Evidence(chunkId: "p99.1", locator: "p. 99", concept: "ATP")])

    XCTAssertEqual(problem(payload), .unknownPassage("p99.1"))
  }

  func testEvidenceLocatorIgnoresCaseAndAccentsButNotThePage() {
    let chapter = StudyPassage(
      id: "c2.1",
      locator: .epub(href: "ch2.xhtml", chapter: 2, chapterTitle: "Método", progression: 0),
      text: "O método tem três passos."
    )
    let request = Fixtures.request(passages: [chapter])
    let matching = Fixtures.payload(
      evidence: [Evidence(chunkId: "c2.1", locator: "CH. 2:  metodo", concept: "passos")])
    let otherPage = Fixtures.payload(
      evidence: [Evidence(chunkId: "p41.1", locator: "p. 40", concept: "ATP")])

    XCTAssertNotNil(try? validate(matching, request).get())
    XCTAssertEqual(problem(otherPage), .locatorMismatch("p41.1"))
  }
}
