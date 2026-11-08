import Foundation

enum StudyLanguage: String, Codable, CaseIterable, Equatable {
  case portugueseBrazil = "pt-BR"
  case englishUS = "en-US"

  var promptName: String {
    switch self {
    case .portugueseBrazil: return "Brazilian Portuguese"
    case .englishUS: return "American English"
    }
  }

  var settingsLabel: String {
    switch self {
    case .portugueseBrazil: return "Português (Brasil)"
    case .englishUS: return "English (US)"
    }
  }
}
