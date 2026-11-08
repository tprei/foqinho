import SwiftUI

struct StudyConsentView: View {
  private let consent: StudyConsentDisplay
  private let onAllow: () -> Void
  private let onCancel: () -> Void

  init(
    consent: StudyConsentDisplay,
    onAllow: @escaping () -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.consent = consent
    self.onAllow = onAllow
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Label(title, systemImage: "hand.raised")
        .font(.title2.bold())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      switch consent {
      case .provider(let host, let mode):
        Text("Sent to \(host)")
          .font(.headline)
        VStack(alignment: .leading, spacing: 12) {
          consentLine("This conversation's transcripts", symbol: "text.bubble")
          consentLine("The book's title, author and position", symbol: "book.closed")
          if mode == .document {
            consentLine(
              "Up to 12,000 characters of passages from your file", symbol: "text.alignleft")
          }
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("Never sent to this provider")
            .font(.headline)
          Text("Audio, the whole book or other apps' data.")
            .font(.body)
          Text(
            "Transcripts and passages are cleared when you close this conversation. This permission is remembered for this host; revoke it in Settings."
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
      case .serverSpeech(let language):
        Text("On-device recognition isn't available for \(language.settingsLabel) on this iPhone.")
        Text(
          "Apple will receive your microphone audio to transcribe it. Server recognition stops after about a minute, so keep each answer short."
        )
        Text("Foqos doesn't save your audio. You can turn off server speech in Settings.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 8) {
        StudyActionButton("Allow", isProminent: true, action: onAllow)
        Button("Cancel", role: .cancel, action: onCancel)
          .font(.headline)
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, minHeight: 44)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.12))
    }
    .accessibilityElement(children: .contain)
  }

  private var title: String {
    switch consent {
    case .provider(let host, _): return "Send to \(host)?"
    case .serverSpeech: return "Transcribe with Apple's servers?"
    }
  }

  private func consentLine(_ text: String, symbol: String) -> some View {
    Label(text, systemImage: symbol)
      .font(.body)
      .fixedSize(horizontal: false, vertical: true)
  }
}

#Preview("Consent · document provider") {
  ScrollView {
    StudyConsentView(
      consent: .provider(host: "api.openai.com", mode: .document), onAllow: {}, onCancel: {}
    )
    .padding(24)
  }
  .background(Color(uiColor: .systemGroupedBackground))
  .environmentObject(ThemeManager())
}

#Preview("Consent · model knowledge") {
  ScrollView {
    StudyConsentView(
      consent: .provider(host: "models.example.org", mode: .modelKnowledge), onAllow: {},
      onCancel: {}
    )
    .padding(24)
  }
  .environmentObject(ThemeManager())
}

#Preview("Consent · Apple speech · large type") {
  ScrollView {
    StudyConsentView(
      consent: .serverSpeech(language: .portugueseBrazil), onAllow: {}, onCancel: {}
    )
    .padding(24)
  }
  .environment(\.dynamicTypeSize, .accessibility1)
  .environmentObject(ThemeManager())
}
