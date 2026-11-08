import Foundation

extension StudyProviderConfiguration.ResponseFormat {
  var label: String {
    switch self {
    case .jsonSchema: return "JSON schema"
    case .jsonObject: return "JSON object"
    }
  }
}

enum StudyValidationDisplay: Equatable {
  case success(String)
  case error(String)
}

enum StudySettingsEdit: Equatable {
  case endpointURL(String)
  case modelID(String)
  case responseFormat(StudyProviderConfiguration.ResponseFormat)
  case apiKey(String)
  case language(StudyLanguage)
  case allowServerSpeech(Bool)
}

struct StudySettingsDisplay: Equatable {
  let endpointURL: String
  let modelID: String
  let responseFormat: StudyProviderConfiguration.ResponseFormat
  let apiKey: String
  let isAPIKeySaved: Bool
  let isSaving: Bool
  let canSave: Bool
  let hasUnsavedChanges: Bool
  let validation: StudyValidationDisplay?
  let language: StudyLanguage
  let consentedHosts: [String]
  let allowServerSpeech: Bool
  let documents: [StudyDocumentSummary]
  let importState: StudyImportDisplay
  let recentUnlocks: [StudyUnlockGrant]

  init(
    endpointURL: String,
    modelID: String,
    responseFormat: StudyProviderConfiguration.ResponseFormat = .jsonSchema,
    apiKey: String = "",
    isAPIKeySaved: Bool = false,
    isSaving: Bool = false,
    canSave: Bool = true,
    hasUnsavedChanges: Bool = false,
    validation: StudyValidationDisplay? = nil,
    language: StudyLanguage = .englishUS,
    consentedHosts: [String] = [],
    allowServerSpeech: Bool = false,
    documents: [StudyDocumentSummary] = [],
    importState: StudyImportDisplay = .idle,
    recentUnlocks: [StudyUnlockGrant] = []
  ) {
    self.endpointURL = endpointURL
    self.modelID = modelID
    self.responseFormat = responseFormat
    self.apiKey = apiKey
    self.isAPIKeySaved = isAPIKeySaved
    self.isSaving = isSaving
    self.canSave = canSave
    self.hasUnsavedChanges = hasUnsavedChanges
    self.validation = validation
    self.language = language
    self.consentedHosts = consentedHosts
    self.allowServerSpeech = allowServerSpeech
    self.documents = documents
    self.importState = importState
    self.recentUnlocks = recentUnlocks
  }
}
