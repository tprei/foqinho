import Foundation

final class StudyProviderSettingsStore {
  struct Settings: Codable, Equatable {
    var configuration: StudyProviderConfiguration?
    var language: StudyLanguage = .portugueseBrazil
    var consentedHosts: [String] = []
    var allowsServerSpeech = false
  }

  private static let key = "studyUnlock.settings"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  // Unreadable settings start over from defaults, like the strategy data decoders.
  func load() -> Settings {
    guard let data = defaults.data(forKey: Self.key),
      let settings = try? JSONDecoder().decode(Settings.self, from: data)
    else {
      return Settings()
    }
    return settings
  }

  func save(_ settings: Settings) throws {
    defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
  }

  func hasConsent(host: String) -> Bool {
    load().consentedHosts.contains(host)
  }

  func recordConsent(host: String) throws {
    var settings = load()
    guard !settings.consentedHosts.contains(host) else { return }
    settings.consentedHosts.append(host)
    try save(settings)
  }

  func revokeConsent(host: String) throws {
    var settings = load()
    settings.consentedHosts.removeAll { $0 == host }
    try save(settings)
  }
}
