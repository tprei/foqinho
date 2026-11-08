import SwiftUI

struct StudyActionButton: View {
  @EnvironmentObject private var themeManager: ThemeManager

  private let title: String
  private let systemImage: String?
  private let isProminent: Bool
  private let isLoading: Bool
  private let isDisabled: Bool
  private let minimumHeight: CGFloat
  private let action: () -> Void

  init(
    _ title: String,
    systemImage: String? = nil,
    isProminent: Bool = false,
    isLoading: Bool = false,
    isDisabled: Bool = false,
    minimumHeight: CGFloat = 50,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.systemImage = systemImage
    self.isProminent = isProminent
    self.isLoading = isLoading
    self.isDisabled = isDisabled
    self.minimumHeight = minimumHeight
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        if isLoading {
          ProgressView()
            .tint(isProminent ? Color(uiColor: .systemBackground) : .primary)
        } else if let systemImage {
          Image(systemName: systemImage)
            .accessibilityHidden(true)
        }
        Text(title)
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(.headline)
      .frame(maxWidth: .infinity, minHeight: minimumHeight)
      .padding(.horizontal, 20)
      .padding(.vertical, 4)
      .foregroundStyle(isProminent ? Color(uiColor: .systemBackground) : .primary)
      .background(
        isProminent ? Color.primary : themeManager.themeColor.opacity(0.14),
        in: Capsule()
      )
      .contentShape(Capsule())
      .opacity(isDisabled || isLoading ? 0.55 : 1)
    }
    .buttonStyle(StudyPressStyle())
    .disabled(isDisabled || isLoading)
    .accessibilityLabel(title)
    .accessibilityValue(isLoading ? "In progress" : "")
  }
}

private struct StudyPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.8 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
  }
}

struct StudyModeBadgeView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  private let source: StudySource

  init(source: StudySource) {
    self.source = source
  }

  var body: some View {
    Label {
      Text(label)
        .lineLimit(isDocument ? 2 : nil)
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: isDocument ? "book.closed.fill" : "cloud")
        .accessibilityHidden(true)
    }
    .font(.subheadline.weight(.medium))
    .foregroundStyle(.primary)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      isDocument
        ? themeManager.themeColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(
          Color.secondary.opacity(0.45),
          style: StrokeStyle(lineWidth: 1, dash: isDocument ? [] : [4, 4])
        )
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
  }

  private var isDocument: Bool {
    if case .document = source { return true }
    return false
  }

  private var label: String {
    switch source {
    case .document(let document): return "From your file · \(document.title)"
    case .modelKnowledge: return "From the model's knowledge · may be wrong"
    }
  }
}

struct StudyDocumentRow: View {
  private let document: StudyDocumentSummary

  init(document: StudyDocumentSummary) {
    self.document = document
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: document.format == .pdf ? "doc.richtext" : "book.closed")
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 32)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(document.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
        if let author = document.author, !author.isEmpty {
          Text(author)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Text(
          "\(document.format.rawValue.uppercased()) · \(document.passageCount) \(document.passageCount == 1 ? "passage" : "passages")"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}

struct StudyEvidenceView: View {
  private enum Content {
    case labels([String])
    case locators([StudyLocator])

    var indices: Range<Int> {
      switch self {
      case .labels(let labels): return labels.indices
      case .locators(let locators): return locators.indices
      }
    }

    func label(at index: Int) -> String {
      switch self {
      case .labels(let labels): return labels[index]
      case .locators(let locators): return locators[index].label
      }
    }
  }

  private let content: Content

  init(labels: [String]) {
    content = .labels(labels)
  }

  init(locators: [StudyLocator]) {
    content = .locators(locators)
  }

  var body: some View {
    if !content.indices.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text("From your file")
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
        ForEach(content.indices, id: \.self) { index in
          Label(content.label(at: index), systemImage: "text.book.closed")
            .font(.subheadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

#Preview("Study controls · light") {
  VStack(spacing: 20) {
    StudyModeBadgeView(source: .document(StudyPreviewData.document))
    StudyModeBadgeView(source: .modelKnowledge(remembered: nil))
    StudyDocumentRow(document: StudyPreviewData.document)
    StudyEvidenceView(labels: ["p. 42", "ch. 3: The attention economy"])
    StudyActionButton("Talk", systemImage: "mic.fill", isProminent: true, minimumHeight: 88) {}
    StudyActionButton("Importing…", isLoading: true) {}
  }
  .padding(24)
  .environmentObject(ThemeManager())
}

#Preview("Study controls · dark · large type") {
  VStack(spacing: 20) {
    StudyModeBadgeView(source: .modelKnowledge(remembered: nil))
    StudyActionButton("Talk", systemImage: "mic.fill", isProminent: true, minimumHeight: 88) {}
    StudyActionButton("Try again", isDisabled: true) {}
  }
  .padding(24)
  .preferredColorScheme(.dark)
  .environment(\.dynamicTypeSize, .accessibility2)
  .environmentObject(ThemeManager())
}
