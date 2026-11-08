import Foundation

struct StudySubject: Codable, Equatable {
  let title: String
  let author: String?
  let position: String
}

enum StudyTurn: Equatable {
  case explanation(String)
  case followUp(question: String, answer: String)
}

enum StudySource: Equatable {
  case document(StudyDocumentSummary)
  case modelKnowledge(remembered: StudySubject?)
}

struct StudyEvaluationRequest: Equatable {
  let mode: StudyMode
  let language: StudyLanguage
  let subject: StudySubject
  let passages: [StudyPassage]
  let turns: [StudyTurn]
  let followUpsRemaining: Int
}
