import SwiftUI

struct StudyResultView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  private let display: StudyResultDisplay
  private let onTryAgain: () -> Void
  private let onDone: () -> Void

  init(
    display: StudyResultDisplay,
    onTryAgain: @escaping () -> Void,
    onDone: @escaping () -> Void
  ) {
    self.display = display
    self.onTryAgain = onTryAgain
    self.onDone = onDone
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Image(systemName: isApproved ? "checkmark.circle.fill" : "bubble.left.and.bubble.right")
          .font(.system(size: 44, weight: .medium))
          .foregroundStyle(.primary)
          .padding(20)
          .background(themeManager.themeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
          .accessibilityHidden(true)

        Group {
          switch display.outcome {
          case .approved(let until):
            Text("Unlocked until \(until, format: .dateTime.hour().minute())")
              .monospacedDigit()
          case .declined:
            Text("Not unlocked yet")
          }
        }
        .font(.largeTitle.bold())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

        Text(display.feedback)
          .font(.title3)
          .fixedSize(horizontal: false, vertical: true)

        if display.mode == .document {
          StudyEvidenceView(locators: display.evidence)
        } else {
          Label("Based on the model's knowledge", systemImage: "cloud")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: 640, alignment: .leading)
      .frame(maxWidth: .infinity)
      .padding(24)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 8) {
        if !isApproved {
          StudyActionButton("Try again", isProminent: true, action: onTryAgain)
        }
        StudyActionButton("Done", isProminent: isApproved, action: onDone)
      }
      .frame(maxWidth: 640)
      .padding(.horizontal, 24)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity)
      .background(.bar)
    }
  }

  private var isApproved: Bool {
    if case .approved = display.outcome { return true }
    return false
  }
}

#Preview("Result · approved · document") {
  StudyResultView(
    display: StudyResultDisplay(
      outcome: .approved(until: StudyPreviewData.end), mode: .document,
      feedback:
        "You connected deep work to attention residue and explained why switching tasks has a cost.",
      evidence: [.pdfPage(42), .pdfPage(46)]
    ),
    onTryAgain: {}, onDone: {}
  )
  .environment(\.locale, Locale(identifier: "en_GB"))
  .environment(\.timeZone, .gmt)
  .environmentObject(ThemeManager())
}

#Preview("Result · approved · model knowledge") {
  StudyResultView(
    display: StudyResultDisplay(
      outcome: .approved(until: StudyPreviewData.end), mode: .modelKnowledge,
      feedback: "You explained the central idea clearly and supported it with your own example."
    ),
    onTryAgain: {}, onDone: {}
  )
  .preferredColorScheme(.dark)
  .environmentObject(ThemeManager())
}

#Preview("Result · declined") {
  StudyResultView(
    display: StudyResultDisplay(
      outcome: .declined, mode: .document,
      feedback:
        "I couldn't connect your explanation to these passages. Try explaining how task switching affects attention."
    ),
    onTryAgain: {}, onDone: {}
  )
  .environmentObject(ThemeManager())
}
