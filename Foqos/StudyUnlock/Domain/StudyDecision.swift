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
