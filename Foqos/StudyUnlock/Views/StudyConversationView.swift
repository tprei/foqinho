import SwiftUI

struct StudyConversationView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isTranscriptExpanded = false

  private let display: StudyConversationDisplay
  private let onTalkToggle: () -> Void
  private let onFailureAction: () -> Void
  private let onAllowConsent: () -> Void
  private let onCancelConsent: () -> Void

  init(
    display: StudyConversationDisplay,
    onTalkToggle: @escaping () -> Void,
    onFailureAction: @escaping () -> Void,
    onAllowConsent: @escaping () -> Void,
    onCancelConsent: @escaping () -> Void
  ) {
    self.display = display
    self.onTalkToggle = onTalkToggle
    self.onFailureAction = onFailureAction
    self.onAllowConsent = onAllowConsent
    self.onCancelConsent = onCancelConsent
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        StudyModeBadgeView(source: display.source)
        if let position = display.positionLabel, !position.isEmpty {
          Label(position, systemImage: "bookmark")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 16)
      .padding(.bottom, 12)

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if display.followUpNumber > 0 {
            Text("Follow-up \(display.followUpNumber) of 2")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.secondary)
          }

          Text(display.spokenLine)
            .font(.title.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Foqos said: \(display.spokenLine)")

          if let consent = display.consent {
            StudyConsentView(consent: consent, onAllow: onAllowConsent, onCancel: onCancelConsent)
          }

          if let failure = display.failure {
            VStack(alignment: .leading, spacing: 12) {
              Label(failure.message, systemImage: "exclamationmark.triangle")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
              StudyActionButton(failure.action.label, action: onFailureAction)
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
              RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.18))
            }
          }

          if !display.transcript.isEmpty {
            DisclosureGroup("Show transcript", isExpanded: $isTranscriptExpanded) {
              VStack(alignment: .leading, spacing: 20) {
                ForEach(display.transcript) { line in
                  VStack(alignment: .leading, spacing: 6) {
                    Text(line.speaker == .app ? "Foqos" : "You")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                    Text(line.text)
                      .font(.body)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .accessibilityElement(children: .combine)
                }
              }
              .padding(.top, 16)
            }
            .font(.subheadline)
            .tint(.primary)
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
      }
      .defaultScrollAnchor(.top)
    }
    .frame(maxWidth: 720)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(uiColor: .systemGroupedBackground))
    .interactiveDismissDisabled()
    .navigationBarBackButtonHidden()
    .safeAreaInset(edge: .bottom, spacing: 0) {
      talkControls
    }
    .onChange(of: statusLabel) { _, label in
      AccessibilityNotification.Announcement(label).post()
    }
    .onChange(of: display.failure) { _, failure in
      if let failure {
        AccessibilityNotification.Announcement(failure.message).post()
      }
    }
    .onChange(of: display.consent) { _, consent in
      if consent != nil {
        AccessibilityNotification.Announcement(
          "Permission needed. Review what is shared before allowing."
        ).post()
      }
    }
    .sensoryFeedback(.impact(weight: .medium), trigger: display.phase.isListening)
  }

  private var talkControls: some View {
    VStack(spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: display.phase.symbol)
          .accessibilityHidden(true)
        Text(statusLabel)
          .font(.subheadline.weight(.medium))
        if let elapsed = display.phase.elapsedLabel, display.consent == nil, display.failure == nil
        {
          Text("\(elapsed) / 3:00")
            .font(.system(.subheadline, design: .monospaced, weight: .medium))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: elapsed)
        }
      }
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Conversation status")
      .accessibilityValue(accessibilityStatus)

      StudyActionButton(
        display.phase.isListening ? "Stop" : "Talk",
        systemImage: display.phase.isListening ? "stop.fill" : "mic.fill",
        isProminent: true,
        isDisabled: !canTalk,
        minimumHeight: 88,
        action: onTalkToggle
      )
      .accessibilityHint(display.phase.isListening ? "Finish your answer" : "Start answering aloud")
    }
    .frame(maxWidth: 640)
    .padding(.horizontal, 24)
    .padding(.top, 12)
    .padding(.bottom, 12)
    .frame(maxWidth: .infinity)
    .background(.bar)
  }

  private var canTalk: Bool {
    display.phase.canTalk && display.consent == nil && display.failure == nil
  }

  private var statusLabel: String {
    if display.consent != nil { return "Permission needed" }
    if display.failure != nil { return "Conversation paused" }
    return display.phase.label
  }

  private var accessibilityStatus: String {
    if let elapsed = display.phase.elapsedLabel, canTalk {
      return "Listening, \(elapsed) elapsed. Maximum 3 minutes."
    }
    return statusLabel
  }
}

private enum ConversationPreview {
  static let transcript = [
    StudyTranscriptLine(id: "app-1", speaker: .app, text: "What did you take away from this part?"),
    StudyTranscriptLine(
      id: "you-1", speaker: .you,
      text:
        "When I switch tasks, some of my attention stays with the last one. Setting aside uninterrupted time helps me get past that residue."
    ),
    StudyTranscriptLine(
      id: "app-2", speaker: .app,
      text: "How would you protect that uninterrupted time in your own day?"
    ),
  ]

  static func conversationView(
    phase: StudyConversationPhase,
    usesDocument: Bool = true,
    failure: StudyFailureDisplay? = nil,
    consent: StudyConsentDisplay? = nil
  ) -> some View {
    StudyConversationView(
      display: StudyConversationDisplay(
        source: usesDocument
          ? .document(StudyPreviewData.document)
          : .modelKnowledge(remembered: StudyPreviewData.subject),
        positionLabel: "pp. 40–52",
        spokenLine: "How would you protect that uninterrupted time in your own day?",
        phase: phase,
        followUpNumber: 1,
        transcript: transcript,
        failure: failure,
        consent: consent
      ),
      onTalkToggle: {}, onFailureAction: {}, onAllowConsent: {}, onCancelConsent: {}
    )
    .environmentObject(ThemeManager())
  }
}

#Preview("Conversation · ready") {
  ConversationPreview.conversationView(phase: .ready)
}

#Preview("Conversation · speaking") {
  ConversationPreview.conversationView(phase: .speaking)
}

#Preview("Conversation · listening") {
  ConversationPreview.conversationView(phase: .listening(elapsedSeconds: 47))
}

#Preview("Conversation · transcribing") {
  ConversationPreview.conversationView(phase: .transcribing)
}

#Preview("Conversation · evaluating") {
  ConversationPreview.conversationView(phase: .evaluating)
}

#Preview("Conversation · model knowledge") {
  ConversationPreview.conversationView(phase: .ready, usesDocument: false)
    .preferredColorScheme(.dark)
}

#Preview("Conversation · failure") {
  ConversationPreview.conversationView(
    phase: .ready,
    failure: StudyFailureDisplay(message: "Couldn't reach your model. Your answer is still here.")
  )
}

#Preview("Conversation · settings failure") {
  ConversationPreview.conversationView(
    phase: .ready,
    failure: StudyFailureDisplay(message: "Your API key wasn't accepted.", action: .openSettings)
  )
}

#Preview("Conversation · consent") {
  ConversationPreview.conversationView(
    phase: .ready, consent: .provider(host: "api.openai.com", mode: .document)
  )
}
