import SwiftUI

struct StudySourceView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  private let documents: [StudyDocumentSummary]
  private let rememberedSource: StudySource?
  private let isModelConfigured: Bool
  private let importState: StudyImportDisplay
  private let onSelectSource: (StudySource) -> Void
  private let onImport: () -> Void
  private let onOpenSettings: () -> Void

  init(
    documents: [StudyDocumentSummary],
    rememberedSource: StudySource? = nil,
    isModelConfigured: Bool,
    importState: StudyImportDisplay = .idle,
    onSelectSource: @escaping (StudySource) -> Void,
    onImport: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void
  ) {
    self.documents = documents
    self.rememberedSource = rememberedSource
    self.isModelConfigured = isModelConfigured
    self.importState = importState
    self.onSelectSource = onSelectSource
    self.onImport = onImport
    self.onOpenSettings = onOpenSettings
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("Explain what you studied")
          .font(.largeTitle.bold())
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)

        if !isModelConfigured {
          VStack(alignment: .leading, spacing: 12) {
            Label("Set up a model first", systemImage: "gearshape")
              .font(.headline)
            Text("Settings → Study unlock")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            StudyActionButton("Open Settings", systemImage: "gearshape", action: onOpenSettings)
          }
          .padding(16)
          .background(.background, in: RoundedRectangle(cornerRadius: 20))
        }

        if let rememberedSource, let title = rememberedTitle {
          sourceButton(source: rememberedSource) {
            Label {
              VStack(alignment: .leading, spacing: 4) {
                Text("Continue: \(title)")
                  .font(.headline)
                if case .modelKnowledge = rememberedSource {
                  Text("Model knowledge · may be wrong")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                  Text("From your file")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
              }
            } icon: {
              Image(systemName: "arrow.clockwise")
                .foregroundStyle(.secondary)
            }
          }
        }

        VStack(alignment: .leading, spacing: 0) {
          SectionTitle("Your library")
          if documents.isEmpty {
            Label("No documents yet", systemImage: "books.vertical")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(20)
              .background(.background, in: RoundedRectangle(cornerRadius: 20))
          } else {
            VStack(spacing: 0) {
              ForEach(documents) { document in
                sourceButton(source: .document(document)) {
                  StudyDocumentRow(document: document)
                }
                if document.id != documents.last?.id {
                  Divider().padding(.leading, 56)
                }
              }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
          }
        }

        sourceButton(source: .modelKnowledge(remembered: nil)) {
          Label {
            VStack(alignment: .leading, spacing: 6) {
              Text("No file: model knowledge")
                .font(.headline)
              Text("No file to check against. The model may be wrong.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "cloud")
              .foregroundStyle(.secondary)
          }
        }
      }
      .frame(maxWidth: 640, alignment: .leading)
      .frame(maxWidth: .infinity)
      .padding(24)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        if case .failed(let message) = importState {
          Label(message, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(.primary)
            .accessibilityLabel("Import failed. \(message)")
        }
        StudyActionButton(
          importState.isImporting ? "Importing…" : "Import PDF or EPUB",
          systemImage: "plus",
          isLoading: importState.isImporting,
          action: onImport
        )
      }
      .frame(maxWidth: 640)
      .padding(.horizontal, 24)
      .padding(.top, 12)
      .padding(.bottom, 12)
      .frame(maxWidth: .infinity)
      .background(.bar)
    }
    .tint(themeManager.themeColor)
  }

  private var rememberedTitle: String? {
    guard let rememberedSource else { return nil }
    switch rememberedSource {
    case .document(let document): return document.title
    case .modelKnowledge(let subject): return subject?.title
    }
  }

  private func sourceButton<Content: View>(
    source: StudySource,
    @ViewBuilder label: () -> Content
  ) -> some View {
    Button {
      onSelectSource(source)
    } label: {
      HStack(spacing: 12) {
        label()
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .padding(16)
      .foregroundStyle(.primary)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(.background, in: RoundedRectangle(cornerRadius: 20))
    .disabled(!isModelConfigured)
    .accessibilityHint(
      isModelConfigured ? "Start a spoken conversation" : "Set up a model in Settings first")
  }
}

#Preview("Source · library and remembered book") {
  StudySourceView(
    documents: [StudyPreviewData.document, StudyPreviewData.epub],
    rememberedSource: .document(StudyPreviewData.document),
    isModelConfigured: true,
    onSelectSource: { _ in }, onImport: {}, onOpenSettings: {}
  )
  .environmentObject(ThemeManager())
}

#Preview("Source · empty library") {
  StudySourceView(
    documents: [], isModelConfigured: true,
    onSelectSource: { _ in }, onImport: {}, onOpenSettings: {}
  )
  .environmentObject(ThemeManager())
}

#Preview("Source · setup needed · import error") {
  StudySourceView(
    documents: [], isModelConfigured: false,
    importState: .failed("This PDF has no selectable text. Try another file or model knowledge."),
    onSelectSource: { _ in }, onImport: {}, onOpenSettings: {}
  )
  .environmentObject(ThemeManager())
}

#Preview("Source · importing") {
  StudySourceView(
    documents: [StudyPreviewData.document], isModelConfigured: true, importState: .importing,
    onSelectSource: { _ in }, onImport: {}, onOpenSettings: {}
  )
  .environmentObject(ThemeManager())
}
