import Foundation

enum StudyText {
  static func folded(_ text: String) -> String {
    text
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }
}
