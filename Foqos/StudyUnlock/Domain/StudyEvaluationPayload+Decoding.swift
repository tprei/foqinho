import Foundation

extension StudyEvaluationPayload {
  static func decode(from text: String) throws(StudyEvaluationProblem) -> StudyEvaluationPayload {
    let json = unfenced(text.trimmingCharacters(in: .whitespacesAndNewlines))
    do {
      return try JSONDecoder().decode(StudyEvaluationPayload.self, from: Data(json.utf8))
    } catch {
      throw .undecodable
    }
  }

  // Some models wrap JSON in one Markdown fence even when asked for JSON only.
  private static func unfenced(_ text: String) -> String {
    let fence = "```"
    guard text.count > fence.count * 2, text.hasPrefix(fence), text.hasSuffix(fence) else {
      return text
    }

    let inner = text.dropFirst(fence.count).dropLast(fence.count)
    guard let lineEnd = inner.firstIndex(of: "\n") else {
      return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let infoString = inner[..<lineEnd].trimmingCharacters(in: .whitespaces)
    guard infoString.allSatisfy(\.isLetter) else {
      return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return inner[lineEnd...].trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
