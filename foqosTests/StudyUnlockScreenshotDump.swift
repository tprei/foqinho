import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import foqos

// Throwaway, never merged: renders screens in the hosted app at three phone sizes and prints
// them as base64 JPEG so they can be pulled out of the CI log for the PR evidence gist.
@MainActor
final class StudyUnlockScreenshotDump: XCTestCase {
  private let sizes = [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852), CGSize(width: 430, height: 932)]

  private func dump<V: View>(_ name: String, _ view: V) throws {
    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    for size in sizes {
      let window = UIWindow(windowScene: scene)
      window.frame = CGRect(origin: .zero, size: size)
      window.rootViewController = UIHostingController(
        rootView: view.environmentObject(ThemeManager.shared))
      window.makeKeyAndVisible()
      RunLoop.main.run(until: Date().addingTimeInterval(1.2))
      let format = UIGraphicsImageRendererFormat()
      format.scale = 2
      let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
      let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.55))
      print("STUDYSHOT-BEGIN after-\(name)-\(Int(size.width))")
      print(data.base64EncodedString())
      print("STUDYSHOT-END")
      window.isHidden = true
    }
  }

  private var transcript: [StudyTranscriptLine] {
    [
      StudyTranscriptLine(id: "0-you", speaker: .you, text: "A mitocôndria produz ATP a partir de açúcares e oxigênio."),
      StudyTranscriptLine(id: "1-app", speaker: .app, text: "E o que acontece com o oxigênio no fim da cadeia?"),
    ]
  }

  private func conversation(_ display: StudyConversationDisplay) -> some View {
    NavigationStack {
      StudyConversationView(
        display: display, onTalkToggle: {}, onFailureAction: {}, onAllowConsent: {},
        onCancelConsent: {})
    }
  }

  func testDumpStudyScreens() throws {
    try dump(
      "source",
      NavigationStack {
        StudySourceView(
          documents: [StudyPreviewData.document, StudyPreviewData.epub],
          rememberedSource: .modelKnowledge(remembered: StudyPreviewData.subject),
          isModelConfigured: true, onSelectSource: { _ in }, onImport: {}, onOpenSettings: {})
      })
    try dump(
      "listening",
      conversation(
        StudyConversationDisplay(
          source: .document(StudyPreviewData.document), positionLabel: "pp. 40–52",
          spokenLine: "Agora explique, com suas palavras, o que você leu.",
          phase: .listening(elapsedSeconds: 47), transcript: transcript)))
    try dump(
      "consent",
      conversation(
        StudyConversationDisplay(
          source: .modelKnowledge(remembered: StudyPreviewData.subject), positionLabel: "capítulo 10",
          spokenLine:
            "Modo conhecimento do modelo: a avaliação usa o que o modelo sabe sobre o livro e pode errar.",
          phase: .ready, consent: .provider(host: "api.openai.com", mode: .modelKnowledge))))
    try dump(
      "failure",
      conversation(
        StudyConversationDisplay(
          source: .document(StudyPreviewData.document), positionLabel: "pp. 40–52",
          spokenLine: "Não consegui avaliar agora. Nada foi liberado. Toque para tentar de novo.",
          phase: .ready, followUpNumber: 1, transcript: transcript,
          failure: StudyFailureDisplay(message: "You're offline. Nothing was unlocked."))))
    try dump(
      "preparing",
      conversation(
        StudyConversationDisplay(
          source: .document(StudyPreviewData.document), positionLabel: "pp. 40–52",
          spokenLine: "Agora explique, com suas palavras, o que você leu.",
          phase: .preparing, transcript: transcript)))
    try dump(
      "settings-changed",
      conversation(
        StudyConversationDisplay(
          source: .document(StudyPreviewData.document), positionLabel: "pp. 40–52",
          spokenLine: "Agora explique, com suas palavras, o que você leu.",
          phase: .ready, followUpNumber: 1, transcript: transcript,
          failure: StudyFailureDisplay(message: StudyFailureText.message(for: .settingsChanged)))))
    try dump(
      "approved",
      NavigationStack {
        StudyResultView(
          display: StudyResultDisplay(
            outcome: .approved(until: Date().addingTimeInterval(15 * 60)), mode: .document,
            feedback: "Você explicou bem de onde vem o ATP e por que a célula precisa dele.",
            evidence: [.pdfPage(41), .pdfPage(42)]),
          onTryAgain: {}, onDone: {})
      })
    try dump(
      "declined",
      NavigationStack {
        StudyResultView(
          display: StudyResultDisplay(
            outcome: .declined, mode: .modelKnowledge,
            feedback: "Não conheço bem esta edição, e a explicação ficou vaga sobre o ciúme de Bentinho."),
          onTryAgain: {}, onDone: {})
      })
    try dump(
      "study-settings",
      NavigationStack {
        StudySettingsView(
          display: StudySettingsDisplay(
            endpointURL: "https://openrouter.ai/api/v1", modelID: "openai/gpt-5-mini",
            isAPIKeySaved: true, canSave: false,
            validation: .success("Saved. The key is in the Keychain for openrouter.ai."),
            language: .portugueseBrazil, consentedHosts: ["openrouter.ai"],
            documents: [StudyPreviewData.document, StudyPreviewData.epub],
            recentUnlocks: [StudyPreviewData.grant(mode: .document)]),
          onEdit: { _ in }, onSave: {}, onDeleteAPIKey: {}, onRevokeHost: { _ in },
          onDeleteDocument: { _ in }, onImport: {}, onClose: {})
      })
  }

  func testDumpChangedScreens() throws {
    let container = try ModelContainer(
      for: BlockedProfileSession.self, BlockedProfiles.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    defer { SharedData.flushActiveSession() }

    let draft = BlockedProfileDraft()
    draft.enableBreaks = true
    draft.enableStudyUnlock = true
    try dump(
      "profile-form",
      Form {
        BlockedProfileBreaksSection(draft: draft, disabled: false)
        BlockedProfileStudyUnlockSection(draft: draft, disabled: false)
      })

    try dump(
      "settings",
      SettingsView()
        .environmentObject(RequestAuthorizer())
        .environmentObject(StrategyManager())
        .modelContainer(container))

    let profile = BlockedProfiles(
      name: "Deep Work", blockingStrategyId: NFCBlockingStrategy.id, enableStudyUnlock: true)
    context.insert(profile)
    let session = BlockedProfileSession.createSession(
      in: context, withTag: NFCBlockingStrategy.id, withProfile: profile)
    try context.save()
    let manager = StrategyManager()
    manager.activeSession = session
    try dump(
      "active-session",
      ActiveProfileSessionView(
        profile: profile, elapsedTime: 1_500, displayTime: 1_500, isBreakAvailable: false,
        isBreakActive: false, isPauseActive: false, isCountdownExpired: false,
        onBreakTapped: {}, onStopTapped: {}, onExpiredCountdownReset: {}
      )
      .environmentObject(manager)
      .modelContainer(container))

    try dump(
      "active-card",
      VStack(alignment: .leading) {
        StudyActiveUnlockCard(grant: StudyPreviewData.grant(mode: .document))
        Spacer()
      }
      .padding(20))
  }
}
