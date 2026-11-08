import XCTest

@testable import foqos

final class StudyEvaluationDecodingTests: XCTestCase {
  private let json = """
    {"decision":"follow_up","basis":"document","confidence":0.4,
     "coveredConcepts":["ATP"],"missingConcepts":["oxigênio"],"contradictions":[],
     "evidence":[{"chunkId":"p41.1","locator":"p. 41","concept":"ATP"}],
     "nextQuestion":"E o oxigênio?","spokenFeedback":"Faltou o oxigênio."}
    """

  func testDecodesPlainJSON() throws {
    let payload = try StudyEvaluationPayload.decode(from: "\n  \(json)  \n")

    XCTAssertEqual(payload.decision, "follow_up")
    XCTAssertEqual(payload.evidence.first?.chunkId, "p41.1")
    XCTAssertEqual(payload.nextQuestion, "E o oxigênio?")
  }

  func testDecodesJSONInsideOneMarkdownFence() throws {
    let fencedWithLanguage = "```json\n\(json)\n```"
    let fencedBare = "```\n\(json)\n```"

    XCTAssertEqual(
      try StudyEvaluationPayload.decode(from: fencedWithLanguage),
      try StudyEvaluationPayload.decode(from: json)
    )
    XCTAssertEqual(
      try StudyEvaluationPayload.decode(from: fencedBare),
      try StudyEvaluationPayload.decode(from: json)
    )
  }

  func testProseIsUndecodable() {
    XCTAssertThrowsError(
      try StudyEvaluationPayload.decode(from: "Great explanation! I'd say pass.")
    ) { error in
      XCTAssertEqual(error as? StudyEvaluationProblem, .undecodable)
    }
  }

  func testMissingFieldIsUndecodable() {
    let withoutFeedback = json.replacingOccurrences(
      of: ",\"spokenFeedback\":\"Faltou o oxigênio.\"", with: "")

    XCTAssertThrowsError(try StudyEvaluationPayload.decode(from: withoutFeedback)) { error in
      XCTAssertEqual(error as? StudyEvaluationProblem, .undecodable)
    }
  }
}

final class StudyEvaluationSchemaTests: XCTestCase {
  private func schema() throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(StudyEvaluationSchema.json.utf8))
    return try XCTUnwrap(object as? [String: Any])
  }

  func testSchemaRequiresExactlyThePayloadFields() throws {
    let schema = try schema()
    let required = try XCTUnwrap(schema["required"] as? [String])
    let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
    let payloadFields: Set = [
      "decision", "basis", "confidence", "coveredConcepts", "missingConcepts",
      "contradictions", "evidence", "nextQuestion", "spokenFeedback",
    ]

    XCTAssertEqual(Set(required), payloadFields)
    XCTAssertEqual(Set(properties.keys), payloadFields)
    XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
  }

  func testEvidenceItemsAreClosedAndFullyRequired() throws {
    let properties = try XCTUnwrap(try schema()["properties"] as? [String: Any])
    let evidence = try XCTUnwrap(properties["evidence"] as? [String: Any])
    let item = try XCTUnwrap(evidence["items"] as? [String: Any])

    XCTAssertEqual(
      Set(try XCTUnwrap(item["required"] as? [String])), ["chunkId", "locator", "concept"])
    XCTAssertEqual(item["additionalProperties"] as? Bool, false)
  }

  func testSchemaEnumsAreTheValuesTheValidatorAccepts() throws {
    let properties = try XCTUnwrap(try schema()["properties"] as? [String: Any])
    let decisions = try XCTUnwrap((properties["decision"] as? [String: Any])?["enum"] as? [String])
    let bases = try XCTUnwrap((properties["basis"] as? [String: Any])?["enum"] as? [String])

    for decision in decisions {
      let payload = StudyDomainFixtures.payload(decision: decision, nextQuestion: "Por quê?")
      let result = StudyEvaluationValidator.validate(payload, for: StudyDomainFixtures.request())
      XCTAssertNoThrow(try result.get(), "decision \(decision)")
    }
    XCTAssertEqual(Set(bases), [StudyMode.document.rawValue, StudyMode.modelKnowledge.rawValue])
  }
}
