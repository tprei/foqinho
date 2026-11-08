import SwiftUI

struct StudySettingsView: View {
  private enum Field: Hashable {
    case endpoint
    case model
    case apiKey
  }

  @EnvironmentObject private var themeManager: ThemeManager
  @FocusState private var focusedField: Field?
  @State private var isConfirmingClose = false
  @State private var isConfirmingKeyDeletion = false

  private let display: StudySettingsDisplay
  private let onEdit: (StudySettingsEdit) -> Void
  private let onSave: () -> Void
  private let onDeleteAPIKey: () -> Void
  private let onRevokeHost: (String) -> Void
  private let onDeleteDocument: (UUID) -> Void
  private let onImport: () -> Void
  private let onClose: () -> Void

  init(
    display: StudySettingsDisplay,
    onEdit: @escaping (StudySettingsEdit) -> Void,
    onSave: @escaping () -> Void,
    onDeleteAPIKey: @escaping () -> Void,
    onRevokeHost: @escaping (String) -> Void,
    onDeleteDocument: @escaping (UUID) -> Void,
    onImport: @escaping () -> Void,
    onClose: @escaping () -> Void
  ) {
    self.display = display
    self.onEdit = onEdit
    self.onSave = onSave
    self.onDeleteAPIKey = onDeleteAPIKey
    self.onRevokeHost = onRevokeHost
    self.onDeleteDocument = onDeleteDocument
    self.onImport = onImport
    self.onClose = onClose
  }

  var body: some View {
    Form {
      modelSection

      Section("Conversation") {
        Picker(
          "Language",
          selection: Binding(
            get: { display.language },
            set: { onEdit(.language($0)) }
          )
        ) {
          ForEach(StudyLanguage.allCases, id: \.rawValue) { language in
            Text(language.settingsLabel).tag(language)
          }
        }
        .accessibilityLabel("Conversation language")
      }

      privacySection
      librarySection
      recentUnlocksSection
    }
    .disabled(display.isSaving)
    .tint(themeManager.themeColor)
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle("Study unlock")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .interactiveDismissDisabled(display.hasUnsavedChanges || display.isSaving)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button {
          focusedField = nil
          if display.hasUnsavedChanges {
            isConfirmingClose = true
          } else {
            onClose()
          }
        } label: {
          Label("Back", systemImage: "chevron.left")
            .foregroundStyle(.primary)
        }
        .disabled(display.isSaving)
      }
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { focusedField = nil }
          .foregroundStyle(.primary)
      }
    }
    .confirmationDialog(
      "Discard unsaved changes?", isPresented: $isConfirmingClose, titleVisibility: .visible
    ) {
      Button("Discard changes", role: .destructive, action: onClose)
      Button("Keep editing", role: .cancel) {}
    }
    .confirmationDialog(
      "Delete saved API key?", isPresented: $isConfirmingKeyDeletion, titleVisibility: .visible
    ) {
      Button("Delete key", role: .destructive, action: onDeleteAPIKey)
      Button("Cancel", role: .cancel) {}
    }
    .onChange(of: display.validation) { _, validation in
      guard let validation else { return }
      switch validation {
      case .success(let message), .error(let message):
        AccessibilityNotification.Announcement(message).post()
      }
    }
  }

  private var modelSection: some View {
    Section("Model") {
      VStack(alignment: .leading, spacing: 8) {
        Text("Endpoint URL").font(.subheadline.weight(.medium))
        TextField(
          "https://api.example.com/v1",
          text: Binding(get: { display.endpointURL }, set: { onEdit(.endpointURL($0)) })
        )
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($focusedField, equals: .endpoint)
        .submitLabel(.next)
        .onSubmit { focusedField = .model }
        .accessibilityLabel("Endpoint URL")
      }
      .padding(.vertical, 4)

      VStack(alignment: .leading, spacing: 8) {
        Text("Model ID").font(.subheadline.weight(.medium))
        TextField(
          "Model ID",
          text: Binding(get: { display.modelID }, set: { onEdit(.modelID($0)) })
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($focusedField, equals: .model)
        .submitLabel(.next)
        .onSubmit { focusedField = .apiKey }
        .accessibilityLabel("Model ID")
      }
      .padding(.vertical, 4)

      Picker(
        "Response format",
        selection: Binding(get: { display.responseFormat }, set: { onEdit(.responseFormat($0)) })
      ) {
        ForEach(StudyProviderConfiguration.ResponseFormat.allCases, id: \.rawValue) { format in
          Text(format.label).tag(format)
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("API key").font(.subheadline.weight(.medium))
        SecureField(
          display.isAPIKeySaved ? "Leave blank to keep saved key" : "API key",
          text: Binding(get: { display.apiKey }, set: { onEdit(.apiKey($0)) })
        )
        .textContentType(.password)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($focusedField, equals: .apiKey)
        .submitLabel(.done)
        .onSubmit { focusedField = nil }
        .accessibilityLabel("API key")
        .privacySensitive()

        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Label(
            display.isAPIKeySaved ? "Saved in Keychain" : "Not saved",
            systemImage: display.isAPIKeySaved ? "lock.fill" : "key"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          if display.isAPIKeySaved {
            Button("Delete", role: .destructive) {
              focusedField = nil
              isConfirmingKeyDeletion = true
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .accessibilityLabel("Delete saved API key")
          }
        }
      }
      .padding(.vertical, 4)

      StudyActionButton(
        display.isSaving ? "Saving…" : "Save",
        isProminent: true,
        isLoading: display.isSaving,
        isDisabled: !display.canSave
      ) {
        focusedField = nil
        onSave()
      }
      .listRowBackground(Color.clear)

      if let validation = display.validation {
        switch validation {
        case .success(let message):
          Label(message, systemImage: "checkmark.circle")
            .font(.subheadline)
        case .error(let message):
          Label(message, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
        }
      }
    }
  }

  private var privacySection: some View {
    Section("Privacy") {
      VStack(alignment: .leading, spacing: 12) {
        Text("Your endpoint")
          .font(.subheadline.weight(.medium))
        Text(display.endpointURL.isEmpty ? "No endpoint configured" : display.endpointURL)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        Text(
          "Your provider receives this conversation's transcripts and the book's title, author and position. In document mode, it also receives up to 12,000 characters of passages. It never receives audio, the whole book or other apps' data."
        )
        Text(
          "Audio isn't recorded. Transcripts and passages are cleared when the study sheet closes. Your API key is stored in Keychain on this iPhone."
        )
      }
      .font(.subheadline)
      .padding(.vertical, 4)

      if display.consentedHosts.isEmpty {
        Text("No hosts allowed yet")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(display.consentedHosts, id: \.self) { host in
          HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
              Text(host)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
              Text("Allowed host")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Revoke", role: .destructive) { onRevokeHost(host) }
              .buttonStyle(.borderless)
              .frame(minHeight: 44)
              .accessibilityLabel("Revoke permission for \(host)")
          }
        }
      }

      CustomToggle(
        title: "Allow server speech",
        description:
          "When on-device recognition isn't available, Apple receives audio for transcription. Server recognition stops after about a minute.",
        isOn: Binding(get: { display.allowServerSpeech }, set: { onEdit(.allowServerSpeech($0)) })
      )
    }
  }

  private var librarySection: some View {
    Section("Library") {
      if display.documents.isEmpty {
        Label("No documents yet", systemImage: "books.vertical")
          .foregroundStyle(.secondary)
      }
      ForEach(display.documents) { document in
        StudyDocumentRow(document: document)
          .swipeActions {
            Button("Delete", role: .destructive) { onDeleteDocument(document.id) }
          }
      }
      if case .failed(let message) = display.importState {
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.subheadline)
          .accessibilityLabel("Import failed. \(message)")
      }
      StudyActionButton(
        display.importState.isImporting ? "Importing…" : "Import PDF or EPUB",
        systemImage: "plus",
        isLoading: display.importState.isImporting,
        action: onImport
      )
      .listRowBackground(Color.clear)
    }
  }

  private var recentUnlocksSection: some View {
    Section("Recent unlocks") {
      if display.recentUnlocks.isEmpty {
        Text("No study unlocks yet")
          .foregroundStyle(.secondary)
      }
      ForEach(display.recentUnlocks) { grant in
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .firstTextBaseline) {
            Text(grant.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
              .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Int((grant.expiresAt.timeIntervalSince(grant.createdAt) / 60).rounded())) min")
              .monospacedDigit()
          }
          .font(.subheadline.weight(.medium))
          Label(
            grant.mode == .document ? "Document mode" : "Model knowledge · may be wrong",
            systemImage: grant.mode == .document ? "book.closed.fill" : "cloud"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          if grant.mode == .document {
            StudyEvidenceView(labels: grant.evidenceLocators)
          }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
      }
    }
  }
}

private enum SettingsPreview {
  static let settings = StudySettingsDisplay(
    endpointURL: "https://api.openai.com/v1",
    modelID: "gpt-4.1-mini",
    isAPIKeySaved: true,
    canSave: false,
    validation: .success("Model settings saved."),
    language: .englishUS,
    consentedHosts: ["api.openai.com", "models.example.org"],
    documents: [StudyPreviewData.document, StudyPreviewData.epub],
    recentUnlocks: [
      StudyPreviewData.grant(mode: .document), StudyPreviewData.grant(mode: .modelKnowledge),
    ]
  )

  static func settingsView(display: StudySettingsDisplay) -> some View {
    NavigationStack {
      StudySettingsView(
        display: display,
        onEdit: { _ in }, onSave: {}, onDeleteAPIKey: {}, onRevokeHost: { _ in },
        onDeleteDocument: { _ in }, onImport: {}, onClose: {}
      )
    }
    .environmentObject(ThemeManager())
  }
}

#Preview("Settings · configured") {
  SettingsPreview.settingsView(display: SettingsPreview.settings)
}

#Preview("Settings · empty library · unsaved") {
  SettingsPreview.settingsView(
    display: StudySettingsDisplay(
      endpointURL: "", modelID: "", canSave: false, hasUnsavedChanges: true)
  )
}

#Preview("Settings · validation error") {
  SettingsPreview.settingsView(
    display: StudySettingsDisplay(
      endpointURL: "http://models.example.org", modelID: "study-model",
      validation: .error("Use an HTTPS endpoint URL."), documents: [StudyPreviewData.document],
      importState: .failed("This EPUB is protected. Use model knowledge instead.")
    )
  )
}

#Preview("Settings · saving") {
  SettingsPreview.settingsView(
    display: StudySettingsDisplay(
      endpointURL: "https://models.example.org/v1", modelID: "study-model", isSaving: true
    )
  )
}
