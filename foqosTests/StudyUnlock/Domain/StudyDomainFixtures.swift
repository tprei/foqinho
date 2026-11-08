import Foundation

@testable import foqos

enum StudyDomainFixtures {
  static let passages = [
    StudyPassage(id: "p40.1", locator: .pdfPage(40), text: "A célula precisa de energia."),
    StudyPassage(id: "p41.1", locator: .pdfPage(41), text: "As mitocôndrias produzem ATP."),
    StudyPassage(id: "p41.2", locator: .pdfPage(41), text: "O ATP guarda energia química."),
  ]

  static func request(
    mode: StudyMode = .document,
    passages: [StudyPassage]? = nil,
    followUpsRemaining: Int = StudyDecision.maximumFollowUps
  ) -> StudyEvaluationRequest {
    StudyEvaluationRequest(
      mode: mode,
      language: .portugueseBrazil,
      subject: StudySubject(title: "Biologia", author: "Ana Lima", position: "pp. 40–41"),
      passages: passages ?? (mode == .document ? Self.passages : []),
      turns: [.explanation("A mitocôndria faz ATP para a célula.")],
      followUpsRemaining: followUpsRemaining
    )
  }

  static func payload(
    decision: String = "pass",
    basis: String = "document",
    confidence: Double = 0.9,
    coveredConcepts: [String] = ["ATP vem da mitocôndria"],
    missingConcepts: [String] = [],
    contradictions: [String] = [],
    evidence: [StudyEvaluationPayload.Evidence] = [
      StudyEvaluationPayload.Evidence(
        chunkId: "p41.1", locator: "p. 41", concept: "ATP vem da mitocôndria")
    ],
    nextQuestion: String = "",
    spokenFeedback: String = "Você explicou bem a origem do ATP."
  ) -> StudyEvaluationPayload {
    StudyEvaluationPayload(
      decision: decision,
      basis: basis,
      confidence: confidence,
      coveredConcepts: coveredConcepts,
      missingConcepts: missingConcepts,
      contradictions: contradictions,
      evidence: evidence,
      nextQuestion: nextQuestion,
      spokenFeedback: spokenFeedback
    )
  }

  static func evaluation(
    decision: StudyEvaluation.Decision = .pass,
    confidence: Double = 0.9,
    coveredConcepts: [String] = ["ATP vem da mitocôndria"],
    contradictions: [String] = [],
    evidence: [StudyEvidence] = [
      StudyEvidence(passageId: "p41.1", locator: .pdfPage(41), concept: "ATP")
    ],
    nextQuestion: String? = nil,
    spokenFeedback: String = "Boa explicação."
  ) -> StudyEvaluation {
    StudyEvaluation(
      decision: decision,
      confidence: confidence,
      coveredConcepts: coveredConcepts,
      missingConcepts: [],
      contradictions: contradictions,
      evidence: evidence,
      nextQuestion: nextQuestion,
      spokenFeedback: spokenFeedback
    )
  }
}
