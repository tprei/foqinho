import SwiftUI
import UniformTypeIdentifiers

struct StudySettingsScreen: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: StudySettingsModel
  @State private var isPickingFile = false

  init(environment: StudyUnlockEnvironment) {
    _model = StateObject(
      wrappedValue: StudySettingsModel(settings: environment.settings, library: environment.library)
    )
  }

  var body: some View {
    StudySettingsView(
      display: model.display,
      onEdit: { model.apply($0) },
      onSave: { model.save() },
      onDeleteAPIKey: { model.deleteAPIKey() },
      onRevokeHost: { model.revoke(host: $0) },
      onDeleteDocument: { model.deleteDocument(id: $0) },
      onImport: { isPickingFile = true },
      onClose: { dismiss() }
    )
    .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.pdf, .epub]) { result in
      switch result {
      case .success(let url):
        Task { await model.importDocument(from: url) }
      case .failure:
        model.importFailed()
      }
    }
  }
}
