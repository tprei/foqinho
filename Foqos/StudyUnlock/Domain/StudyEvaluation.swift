import Foundation

struct StudyEvaluationPayload: Decodable, Equatable {
  struct Evidence: Decodable, Equatable {
    let chunkId: String
    let locator: String
    let concept: String
  }

  let decision: String
  let basis: String
  let confidence: Double
  let coveredConcepts: [String]
  let missingConcepts: [String]
  let contradictions: [String]
  let evidence: [Evidence]
  let nextQuestion: String
  let spokenFeedback: String
}

struct StudyEvidence: Equatable {
  let passageId: String
  let locator: StudyLocator
  let concept: String
}

struct StudyEvaluation: Equatable {
  enum Decision: Equatable {
    case pass
    case followUp
    case abstain
  }

  let decision: Decision
  let confidence: Double
  let coveredConcepts: [String]
  let missingConcepts: [String]
  let contradictions: [String]
  let evidence: [StudyEvidence]
  let nextQuestion: String?
  let spokenFeedback: String
}

enum StudyEvaluationProblem: Error, Equatable {
  case undecodable
  case unknownDecision
  case basisMismatch
  case confidenceOutOfRange
  case emptyField(String)
  case fieldTooLong(String)
  case tooManyItems(String)
  case unknownPassage(String)
  case locatorMismatch(String)
  case evidenceWithoutDocument
  case missingNextQuestion
}

enum StudyEvaluationSchema {
  static let name = "study_evaluation"

  static let json = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "decision", "basis", "confidence", "coveredConcepts", "missingConcepts",
        "contradictions", "evidence", "nextQuestion", "spokenFeedback"
      ],
      "properties": {
        "decision": { "type": "string", "enum": ["pass", "follow_up", "abstain"] },
        "basis": { "type": "string", "enum": ["document", "model_knowledge"] },
        "confidence": { "type": "number" },
        "coveredConcepts": { "type": "array", "items": { "type": "string" } },
        "missingConcepts": { "type": "array", "items": { "type": "string" } },
        "contradictions": { "type": "array", "items": { "type": "string" } },
        "evidence": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["chunkId", "locator", "concept"],
            "properties": {
              "chunkId": { "type": "string" },
              "locator": { "type": "string" },
              "concept": { "type": "string" }
            }
          }
        },
        "nextQuestion": { "type": "string" },
        "spokenFeedback": { "type": "string" }
      }
    }
    """
}
