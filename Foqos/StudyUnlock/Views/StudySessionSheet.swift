import SwiftUI
import UniformTypeIdentifiers

struct StudySessionSheet: View {
  private static let listeningLimit: TimeInterval = 180

  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @StateObject private var model: StudySessionModel
  @State private var documents: [StudyDocumentSummary] = []
  @State private var rememberedSubject: StudySubject?
  @State private var isModelConfigured = false
  @State private var importState: StudyImportDisplay = .idle
  @State private var isPickingFile = false
  @State private var isConfirmingClose = false
  @State private var showingSettings = false
  @State private var isAudioUnavailable = false

  private let environment: StudyUnlockEnvironment
  private let reportError: (String) -> Void

  // reportError outlives the sheet, so a failure on teardown still reaches the person.
  init(
    environment: StudyUnlockEnvironment,
    reportError: @escaping (String) -> Void,
    unlock: @escaping (StudyApproval) throws -> StudyUnlockGrant
  ) {
    self.environment = environment
    self.reportError = reportError
    _model = StateObject(
      wrappedValue: StudySessionModel(dependencies: environment.sessionDependencies(unlock: unlock))
    )
  }

  var body: some View {
    NavigationStack {
      content
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Close", action: requestClose)
          }
        }
    }
    .interactiveDismissDisabled(isConversationRunning)
    .confirmationDialog(
      "End this conversation?", isPresented: $isConfirmingClose, titleVisibility: .visible
    ) {
      Button("End conversation", role: .destructive, action: close)
      Button("Keep talking", role: .cancel) {}
    } message: {
      Text("Your answers so far are discarded and nothing is unlocked.")
    }
    .alert("Audio is unavailable", isPresented: $isAudioUnavailable) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Another app may be using the microphone. Close it and try again.")
    }
    .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.pdf, .epub]) { result in
      importFile(result)
    }
    .sheet(isPresented: $showingSettings, onDismiss: settingsDidClose) {
      NavigationStack {
        StudySettingsScreen(environment: environment)
      }
    }
    .task(id: model.activity) {
      await finishAtTheListeningLimit()
    }
    .onAppear {
      activateAudio()
      refreshSources()
    }
    .onDisappear {
      model.close()
      releaseAudio()
    }
  }

  @ViewBuilder
  private var content: some View {
    if let result = resultDisplay {
      StudyResultView(
        display: result,
        onTryAgain: { Task { await model.restart() } },
        onDone: close
      )
    } else if let conversation = model.conversation {
      TimelineView(.periodic(from: .now, by: 1)) { timeline in
        StudyConversationView(
          display: conversationDisplay(for: conversation, at: timeline.date),
          onTalkToggle: { Task { await model.toggleListening() } },
          onFailureAction: handleFailureAction,
          onAllowConsent: { Task { await model.acceptConsent() } },
          onCancelConsent: close
        )
      }
    } else {
      StudySourceView(
        documents: documents,
        rememberedSource: rememberedSubject.map { .modelKnowledge(remembered: $0) },
        isModelConfigured: isModelConfigured,
        importState: sourceImportState,
        onSelectSource: { source in Task { await model.begin(with: source) } },
        onImport: { isPickingFile = true },
        onOpenSettings: { showingSettings = true }
      )
    }
  }

  private var isConversationRunning: Bool {
    model.conversation != nil && resultDisplay == nil
  }

  private var sourceImportState: StudyImportDisplay {
    switch model.failure {
    case .some(let failure)
    where failure == .documentUnavailable || failure == .missingCredential:
      return .failed(StudyFailureText.message(for: failure))
    default:
      return importState
    }
  }

  private var resultDisplay: StudyResultDisplay? {
    guard let conversation = model.conversation, case .finished(let step) = conversation.phase
    else {
      return nil
    }
    switch step {
    case .approve(let approval, let feedback):
      guard let grant = model.grant else { return nil }
      return StudyResultDisplay(
        outcome: .approved(until: grant.expiresAt),
        mode: approval.mode,
        feedback: feedback,
        evidence: approval.evidenceLocators
      )
    case .decline(_, let feedback):
      return StudyResultDisplay(outcome: .declined, mode: conversation.mode, feedback: feedback)
    case .askFollowUp:
      return nil
    }
  }

  private func conversationDisplay(
    for conversation: StudyConversation,
    at date: Date
  ) -> StudyConversationDisplay {
    StudyConversationDisplay(
      source: conversation.source,
      positionLabel: conversation.subject?.position,
      spokenLine: model.spokenLine ?? "",
      phase: phase(at: date),
      followUpNumber: conversation.followUpsAsked,
      transcript: transcriptLines(of: conversation),
      failure: failureDisplay,
      consent: consentDisplay(for: conversation)
    )
  }

  private func phase(at date: Date) -> StudyConversationPhase {
    switch model.activity {
    case .idle: return .ready
    case .preparing: return .preparing
    case .speaking: return .speaking
    case .listening(let since):
      return .listening(elapsedSeconds: Int(date.timeIntervalSince(since)))
    case .transcribing: return .transcribing
    case .evaluating: return .evaluating
    }
  }

  private var failureDisplay: StudyFailureDisplay? {
    switch model.failure {
    case nil, .needsProviderConsent, .needsServerSpeechConsent:
      return nil
    case .some(let failure):
      return StudyFailureDisplay(
        message: StudyFailureText.message(for: failure),
        action: StudyFailureText.opensSettings(failure) ? .openSettings : .tryAgain
      )
    }
  }

  private func consentDisplay(for conversation: StudyConversation) -> StudyConsentDisplay? {
    switch model.failure {
    case .needsProviderConsent(let host):
      return .provider(host: host, mode: conversation.mode)
    case .needsServerSpeechConsent:
      return .serverSpeech(language: conversation.language)
    default:
      return nil
    }
  }

  private func transcriptLines(of conversation: StudyConversation) -> [StudyTranscriptLine] {
    conversation.turns.enumerated().flatMap { offset, turn -> [StudyTranscriptLine] in
      switch turn {
      case .explanation(let text):
        return [StudyTranscriptLine(id: "\(offset)-you", speaker: .you, text: text)]
      case .followUp(let question, let answer):
        return [
          StudyTranscriptLine(id: "\(offset)-app", speaker: .app, text: question),
          StudyTranscriptLine(id: "\(offset)-you", speaker: .you, text: answer),
        ]
      }
    }
  }

  private func handleFailureAction() {
    switch model.failure {
    case .microphoneDenied, .speechRecognitionDenied:
      if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    case .some(let failure) where StudyFailureText.opensSettings(failure):
      showingSettings = true
    case .unlockFailed, .consentNotSaved:
      Task { await model.restart() }
    default:
      Task { await model.retry() }
    }
  }

  private func finishAtTheListeningLimit() async {
    guard case .listening(let since) = model.activity else { return }
    let remaining = Self.listeningLimit - Date().timeIntervalSince(since)
    do {
      try await Task.sleep(for: .seconds(max(remaining, 0)))
    } catch {
      return
    }
    guard model.activity == .listening(since: since) else { return }
    await model.toggleListening()
  }

  private func requestClose() {
    if isConversationRunning {
      isConfirmingClose = true
    } else {
      close()
    }
  }

  private func close() {
    model.close()
    dismiss()
  }

  private func releaseAudio() {
    do {
      try StudyAudioSession.deactivate()
    } catch {
      reportError(
        "Foqos couldn't hand the audio back to other apps. Restart your music if it stays paused.")
    }
  }

  private func settingsDidClose() {
    refreshSources()
    model.settingsDidChange()
  }

  private func activateAudio() {
    do {
      try StudyAudioSession.activate()
    } catch {
      isAudioUnavailable = true
    }
  }

  private func refreshSources() {
    isModelConfigured = environment.isModelConfigured
    rememberedSubject = environment.library.rememberedSubject
    do {
      documents = try environment.library.documents()
    } catch {
      documents = []
      importState = .failed("Couldn't read the study library.")
    }
  }

  private func importFile(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else {
      importState = .failed("Foqos couldn't open that file.")
      return
    }
    importState = .importing
    Task {
      do {
        _ = try await environment.library.importDocument(from: url, now: Date())
        importState = .idle
      } catch {
        importState = .failed(error.localizedDescription)
      }
      refreshSources()
    }
  }
}
