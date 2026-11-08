import Foundation

enum StudyStep: Equatable {
  case approve(StudyApproval, feedback: String)
  case askFollowUp(question: String, feedback: String)
  case decline(StudyDeclineReason, feedback: String)
}

enum StudyDeclineReason: Equatable {
  case abstained
  case followUpLimitReached
  case contradictions
  case insufficientEvidence
  case lowConfidence
}

// Only StudyDecision, in this file, can approve a conversation.
struct StudyApproval: Equatable {
  let mode: StudyMode
  let approvedAt: Date
  let coveredConceptCount: Int
  let evidenceLocators: [StudyLocator]
  let followUpCount: Int

  fileprivate init(
    mode: StudyMode,
    approvedAt: Date,
    coveredConceptCount: Int,
    evidenceLocators: [StudyLocator],
    followUpCount: Int
  ) {
    self.mode = mode
    self.approvedAt = approvedAt
    self.coveredConceptCount = coveredConceptCount
    self.evidenceLocators = evidenceLocators
    self.followUpCount = followUpCount
  }
}

enum StudyDecision {
  static let maximumFollowUps = 2
  static let minimumPassConfidence = 0.6
}

extension StudyDecision {
  static func next(
    after evaluation: StudyEvaluation,
    request: StudyEvaluationRequest,
    followUpsAsked: Int,
    decidedAt: Date
  ) -> StudyStep {
    let feedback = evaluation.spokenFeedback
    let followUpQuestion = followUpsAsked < maximumFollowUps ? evaluation.nextQuestion : nil

    switch evaluation.decision {
    case .abstain:
      return .decline(.abstained, feedback: feedback)
    case .followUp:
      guard let followUpQuestion else {
        return .decline(.followUpLimitReached, feedback: feedback)
      }
      return .askFollowUp(question: followUpQuestion, feedback: feedback)
    case .pass:
      guard let problem = passProblem(in: evaluation, mode: request.mode) else {
        let approval = StudyApproval(
          mode: request.mode,
          approvedAt: decidedAt,
          coveredConceptCount: evaluation.coveredConcepts.count,
          evidenceLocators: evidenceLocators(of: evaluation, in: request),
          followUpCount: followUpsAsked
        )
        return .approve(approval, feedback: feedback)
      }
      guard let followUpQuestion else { return .decline(problem, feedback: feedback) }
      return .askFollowUp(question: followUpQuestion, feedback: feedback)
    }
  }

  private static func passProblem(
    in evaluation: StudyEvaluation,
    mode: StudyMode
  ) -> StudyDeclineReason? {
    if !evaluation.contradictions.isEmpty { return .contradictions }
    if evaluation.coveredConcepts.isEmpty { return .insufficientEvidence }
    if mode == .document && evaluation.evidence.isEmpty { return .insufficientEvidence }
    if evaluation.confidence < minimumPassConfidence { return .lowConfidence }
    return nil
  }

  private static func evidenceLocators(
    of evaluation: StudyEvaluation,
    in request: StudyEvaluationRequest
  ) -> [StudyLocator] {
    let citedIds = Set(evaluation.evidence.map(\.passageId))
    var seen: Set<StudyLocator> = []
    return request.passages
      .filter { citedIds.contains($0.id) }
      .map(\.locator)
      .filter { seen.insert($0).inserted }
  }
}
