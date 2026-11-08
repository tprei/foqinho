import SwiftUI

struct StudyActiveUnlockCard: View {
  private let grant: StudyUnlockGrant

  init(grant: StudyUnlockGrant) {
    self.grant = grant
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Study unlock · ends \(grant.expiresAt, format: .dateTime.hour().minute())")
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)

      Label(
        grant.mode == .document ? "Document mode" : "Model knowledge · may be wrong",
        systemImage: grant.mode == .document ? "book.closed.fill" : "cloud"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if grant.mode == .document {
        StudyEvidenceView(labels: grant.evidenceLocators)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
      Color.primary.opacity(0.045),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .accessibilityElement(children: .combine)
  }
}

#Preview("Active study unlock · document") {
  StudyActiveUnlockCard(grant: StudyPreviewData.grant(mode: .document))
    .padding(24)
    .environment(\.locale, Locale(identifier: "en_GB"))
    .environment(\.timeZone, .gmt)
}

#Preview("Active study unlock · model knowledge · dark") {
  StudyActiveUnlockCard(grant: StudyPreviewData.grant(mode: .modelKnowledge))
    .padding(24)
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility1)
}
