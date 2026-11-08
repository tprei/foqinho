import Foundation

enum StudyImportDisplay: Equatable {
  case idle
  case importing
  case failed(String)

  var isImporting: Bool {
    self == .importing
  }
}

struct StudyResultDisplay: Equatable {
  enum Outcome: Equatable {
    case approved(until: Date)
    case declined
  }

  let outcome: Outcome
  let mode: StudyMode
  let feedback: String
  let evidence: [StudyLocator]

  init(outcome: Outcome, mode: StudyMode, feedback: String, evidence: [StudyLocator] = []) {
    self.outcome = outcome
    self.mode = mode
    self.feedback = feedback
    self.evidence = evidence
  }
}
