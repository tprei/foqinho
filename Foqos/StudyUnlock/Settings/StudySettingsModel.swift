import Combine
import Foundation

@MainActor
final class StudySettingsModel: ObservableObject {
  private struct ModelDraft: Equatable {
    var endpointURL: String
    var modelID: String
    var responseFormat: StudyProviderConfiguration.ResponseFormat
  }

  @Published private(set) var display: StudySettingsDisplay

  private let settings: StudyProviderSettingsStore
  private let library: StudyLibrary
  private var saved: ModelDraft
  private var draft: ModelDraft
  private var apiKeyDraft = ""
  private var isAPIKeySaved = false
  private var validation: StudyValidationDisplay?
  private var importState: StudyImportDisplay = .idle
  private var documents: [StudyDocumentSummary] = []

  init(settings: StudyProviderSettingsStore, library: StudyLibrary) {
    self.settings = settings
    self.library = library
    let configuration = settings.load().configuration
    saved = ModelDraft(
      endpointURL: configuration?.baseURL.absoluteString ?? "",
      modelID: configuration?.model ?? "",
      responseFormat: configuration?.responseFormat ?? .jsonSchema
    )
    draft = saved
    display = StudySettingsDisplay(endpointURL: saved.endpointURL, modelID: saved.modelID)
    refresh()
  }

  func apply(_ edit: StudySettingsEdit) {
    switch edit {
    case .endpointURL(let value): draft.endpointURL = value
    case .modelID(let value): draft.modelID = value
    case .responseFormat(let value): draft.responseFormat = value
    case .apiKey(let value): apiKeyDraft = value
    case .language(let language): update { $0.language = language }
    case .allowServerSpeech(let isAllowed): update { $0.allowsServerSpeech = isAllowed }
    }
    validation = nil
    publish()
  }

  func save() {
    guard
      let configuration = StudyProviderConfiguration.make(
        baseURL: draft.endpointURL, model: draft.modelID, responseFormat: draft.responseFormat)
    else {
      validation = .error("Use an https:// endpoint and a model ID. Plain HTTP isn't supported.")
      publish()
      return
    }

    do {
      let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      if !key.isEmpty {
        try StudyCredentialStore.save(apiKey: key, host: configuration.host)
      }
      guard try StudyCredentialStore.apiKey(host: configuration.host) != nil else {
        validation = .error("Add the API key for \(configuration.host).")
        publish()
        return
      }
      var current = settings.load()
      current.configuration = configuration
      try settings.save(current)
    } catch {
      validation = .error("Couldn't save the model settings.")
      publish()
      return
    }

    apiKeyDraft = ""
    saved = ModelDraft(
      endpointURL: configuration.baseURL.absoluteString,
      modelID: configuration.model,
      responseFormat: configuration.responseFormat
    )
    draft = saved
    validation = .success("Saved. The key is in the Keychain for \(configuration.host).")
    refresh()
  }

  func deleteAPIKey() {
    guard let host = settings.load().configuration?.host else { return }
    do {
      try StudyCredentialStore.delete(host: host)
      validation = .success("Deleted the key for \(host).")
    } catch {
      validation = .error("Couldn't delete the key.")
    }
    refresh()
  }

  func revoke(host: String) {
    do {
      try settings.revokeConsent(host: host)
    } catch {
      validation = .error("Couldn't revoke \(host).")
    }
    refresh()
  }

  func deleteDocument(id: UUID) {
    do {
      try library.delete(id: id)
    } catch {
      importState = .failed("Couldn't delete that document.")
    }
    refresh()
  }

  func importDocument(from url: URL) async {
    importState = .importing
    publish()
    do {
      _ = try await library.importDocument(from: url, now: Date())
      importState = .idle
    } catch {
      importState = .failed(error.localizedDescription)
    }
    refresh()
  }

  func importFailed() {
    importState = .failed("Foqos couldn't open that file.")
    publish()
  }

  private func update(_ change: (inout StudyProviderSettingsStore.Settings) -> Void) {
    var current = settings.load()
    change(&current)
    do {
      try settings.save(current)
    } catch {
      validation = .error("Couldn't save that setting.")
    }
  }

  private func refresh() {
    do {
      documents = try library.documents()
    } catch {
      documents = []
      importState = .failed("Couldn't read the study library.")
    }
    if let host = settings.load().configuration?.host {
      do {
        isAPIKeySaved = try StudyCredentialStore.apiKey(host: host) != nil
      } catch {
        isAPIKeySaved = false
        validation = .error("Couldn't read the Keychain.")
      }
    } else {
      isAPIKeySaved = false
    }
    publish()
  }

  private func publish() {
    let current = settings.load()
    let hasUnsavedChanges = draft != saved || !apiKeyDraft.isEmpty
    display = StudySettingsDisplay(
      endpointURL: draft.endpointURL,
      modelID: draft.modelID,
      responseFormat: draft.responseFormat,
      apiKey: apiKeyDraft,
      isAPIKeySaved: isAPIKeySaved,
      canSave: hasUnsavedChanges,
      hasUnsavedChanges: hasUnsavedChanges,
      validation: validation,
      language: current.language,
      consentedHosts: current.consentedHosts,
      allowServerSpeech: current.allowsServerSpeech,
      documents: documents,
      importState: importState,
      recentUnlocks: Array(StudyUnlockGrantStore.grants().prefix(20))
    )
  }
}
