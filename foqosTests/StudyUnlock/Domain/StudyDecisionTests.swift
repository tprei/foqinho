import XCTest

@testable import foqos

final class StudyDecisionTests: XCTestCase {
  private typealias Fixtures = StudyDomainFixtures
  private let decidedAt = Date(timeIntervalSince1970: 1_800_000_000)

  private func next(
    _ evaluation: StudyEvaluation,
    mode: StudyMode = .document,
    followUpsAsked: Int = 0
  ) -> StudyStep {
    StudyDecision.next(
      after: evaluation,
      request: Fixtures.request(mode: mode),
      followUpsAsked: followUpsAsked,
      decidedAt: decidedAt
    )
  }

  func testPassWithEvidenceIsApproved() {
    let step = next(Fixtures.evaluation(spokenFeedback: "Muito bem."), followUpsAsked: 1)

    guard case .approve(let approval, let feedback) = step else {
      return XCTFail("Expected approval, got \(step)")
    }
    XCTAssertEqual(feedback, "Muito bem.")
    XCTAssertEqual(approval.mode, .document)
    XCTAssertEqual(approval.approvedAt, decidedAt)
    XCTAssertEqual(approval.coveredConceptCount, 1)
    XCTAssertEqual(approval.evidenceLocators, [.pdfPage(41)])
    XCTAssertEqual(approval.followUpCount, 1)
  }

  func testApprovalListsEachCitedLocatorOnceInReadingOrder() {
    let evidence = [
      StudyEvidence(passageId: "p41.2", locator: .pdfPage(41), concept: "ATP guarda energia"),
      StudyEvidence(passageId: "p40.1", locator: .pdfPage(40), concept: "célula"),
      StudyEvidence(passageId: "p41.1", locator: .pdfPage(41), concept: "mitocôndria"),
    ]

    guard case .approve(let approval, _) = next(Fixtures.evaluation(evidence: evidence)) else {
      return XCTFail("Expected approval")
    }
    XCTAssertEqual(approval.evidenceLocators, [.pdfPage(40), .pdfPage(41)])
  }

  func testModelKnowledgePassNeedsNoEvidence() {
    let step = next(Fixtures.evaluation(evidence: []), mode: .modelKnowledge)

    guard case .approve(let approval, _) = step else { return XCTFail("Expected approval") }
    XCTAssertEqual(approval.mode, .modelKnowledge)
    XCTAssertEqual(approval.evidenceLocators, [])
  }

  func testConfidenceAtTheFloorIsEnough() {
    let step = next(Fixtures.evaluation(confidence: StudyDecision.minimumPassConfidence))

    guard case .approve = step else { return XCTFail("Expected approval, got \(step)") }
  }

  func testWeakPassAsksTheModelsQuestionWhileFollowUpsRemain() {
    let question = "O que acontece sem ATP?"
    let weakPasses = [
      Fixtures.evaluation(
        contradictions: ["disse que o ATP vem do núcleo"], nextQuestion: question),
      Fixtures.evaluation(coveredConcepts: [], nextQuestion: question),
      Fixtures.evaluation(evidence: [], nextQuestion: question),
      Fixtures.evaluation(confidence: 0.59, nextQuestion: question),
    ]

    for evaluation in weakPasses {
      XCTAssertEqual(
        next(evaluation, followUpsAsked: 1),
        .askFollowUp(question: question, feedback: "Boa explicação.")
      )
    }
  }

  func testWeakPassIsDeclinedWithItsReasonWhenNoQuestionCanBeAsked() {
    let feedback = "Boa explicação."
    let question = "O que acontece sem ATP?"

    XCTAssertEqual(
      next(
        Fixtures.evaluation(contradictions: ["núcleo"], nextQuestion: question),
        followUpsAsked: StudyDecision.maximumFollowUps
      ),
      .decline(.contradictions, feedback: feedback)
    )
    XCTAssertEqual(
      next(Fixtures.evaluation(evidence: [])),
      .decline(.insufficientEvidence, feedback: feedback)
    )
    XCTAssertEqual(
      next(Fixtures.evaluation(confidence: 0.3)),
      .decline(.lowConfidence, feedback: feedback)
    )
  }

  func testFollowUpsStopAfterTwo() {
    let evaluation = Fixtures.evaluation(decision: .followUp, nextQuestion: "E o oxigênio?")

    XCTAssertEqual(
      next(evaluation, followUpsAsked: 1),
      .askFollowUp(question: "E o oxigênio?", feedback: "Boa explicação.")
    )
    XCTAssertEqual(
      next(evaluation, followUpsAsked: 2),
      .decline(.followUpLimitReached, feedback: "Boa explicação.")
    )
  }

  func testAbstainIsDeclined() {
    let evaluation = Fixtures.evaluation(
      decision: .abstain, spokenFeedback: "Não consegui avaliar.")

    XCTAssertEqual(next(evaluation), .decline(.abstained, feedback: "Não consegui avaliar."))
  }
}
