import Foundation

enum StudyProviderFactory {
  static func make(
    settings: StudyProviderSettingsStore,
    apiKey: (String) throws -> String? = StudyCredentialStore.apiKey(host:)
  ) throws(StudyProviderError) -> StudyModelProvider {
    guard let configuration = settings.load().configuration else { throw .notConfigured }

    let key: String?
    do {
      key = try apiKey(configuration.host)
    } catch {
      throw .missingCredential
    }
    guard let key, !key.isEmpty else { throw .missingCredential }
    return OpenAICompatibleStudyProvider(configuration: configuration, apiKey: key)
  }
}
