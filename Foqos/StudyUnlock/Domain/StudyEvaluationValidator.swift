import Foundation

enum StudyEvaluationValidator {
  static let maximumItems = 10
  static let maximumConceptLength = 160
  static let maximumQuestionLength = 300
  static let maximumFeedbackLength = 500

  static func validate(
    _ payload: StudyEvaluationPayload,
    for request: StudyEvaluationRequest
  ) -> Result<StudyEvaluation, StudyEvaluationProblem> {
    do {
      return .success(try evaluation(from: payload, for: request))
    } catch {
      return .failure(error)
    }
  }

  private static func evaluation(
    from payload: StudyEvaluationPayload,
    for request: StudyEvaluationRequest
  ) throws(StudyEvaluationProblem) -> StudyEvaluation {
    let decision = try decision(from: payload.decision)
    guard payload.basis == request.mode.rawValue else { throw .basisMismatch }
    guard payload.confidence.isFinite, (0...1).contains(payload.confidence) else {
      throw .confidenceOutOfRange
    }

    let coveredConcepts = try concepts(payload.coveredConcepts, field: "coveredConcepts")
    let missingConcepts = try concepts(payload.missingConcepts, field: "missingConcepts")
    let contradictions = try concepts(payload.contradictions, field: "contradictions")
    guard payload.evidence.count <= maximumItems else { throw .tooManyItems("evidence") }
    let evidenceConcepts = try concepts(payload.evidence.map(\.concept), field: "evidence.concept")

    let spokenFeedback = try text(
      payload.spokenFeedback, field: "spokenFeedback", maximumLength: maximumFeedbackLength)
    let nextQuestion = try question(payload.nextQuestion, for: decision)
    let evidence = try resolvedEvidence(payload.evidence, concepts: evidenceConcepts, for: request)

    return StudyEvaluation(
      decision: decision,
      confidence: payload.confidence,
      coveredConcepts: coveredConcepts,
      missingConcepts: missingConcepts,
      contradictions: contradictions,
      evidence: evidence,
      nextQuestion: nextQuestion,
      spokenFeedback: spokenFeedback
    )
  }

  private static func decision(
    from wireValue: String
  ) throws(StudyEvaluationProblem) -> StudyEvaluation.Decision {
    switch wireValue {
    case "pass": return .pass
    case "follow_up": return .followUp
    case "abstain": return .abstain
    default: throw .unknownDecision
    }
  }

  private static func concepts(
    _ items: [String],
    field: String
  ) throws(StudyEvaluationProblem) -> [String] {
    guard items.count <= maximumItems else { throw .tooManyItems(field) }
    var trimmedItems: [String] = []
    for item in items {
      trimmedItems.append(try text(item, field: field, maximumLength: maximumConceptLength))
    }
    return trimmedItems
  }

  private static func text(
    _ value: String,
    field: String,
    maximumLength: Int
  ) throws(StudyEvaluationProblem) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw .emptyField(field) }
    guard trimmed.count <= maximumLength else { throw .fieldTooLong(field) }
    return trimmed
  }

  private static func question(
    _ value: String,
    for decision: StudyEvaluation.Decision
  ) throws(StudyEvaluationProblem) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count <= maximumQuestionLength else { throw .fieldTooLong("nextQuestion") }
    if trimmed.isEmpty {
      guard decision != .followUp else { throw .missingNextQuestion }
      return nil
    }
    return trimmed
  }

  private static func resolvedEvidence(
    _ items: [StudyEvaluationPayload.Evidence],
    concepts: [String],
    for request: StudyEvaluationRequest
  ) throws(StudyEvaluationProblem) -> [StudyEvidence] {
    guard request.mode == .document else {
      guard items.isEmpty else { throw .evidenceWithoutDocument }
      return []
    }

    let passagesById = Dictionary(
      request.passages.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var evidence: [StudyEvidence] = []
    for (item, concept) in zip(items, concepts) {
      let chunkId = item.chunkId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let passage = passagesById[chunkId] else { throw .unknownPassage(chunkId) }
      guard StudyText.folded(item.locator) == StudyText.folded(passage.locator.label) else {
        throw .locatorMismatch(chunkId)
      }
      evidence.append(
        StudyEvidence(passageId: passage.id, locator: passage.locator, concept: concept))
    }
    return evidence
  }
}
