import Foundation

final class StudyLibrary {
  private static let summaryFileName = "summary.json"
  private static let indexFileName = "index.json"
  private static let rememberedTitleKey = "studyUnlock.rememberedTitle"
  private static let rememberedAuthorKey = "studyUnlock.rememberedAuthor"

  private let root: URL
  private let defaults: UserDefaults
  private let fileManager: FileManager

  init(root: URL, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
    self.root = root
    self.defaults = defaults
    self.fileManager = fileManager
  }

  static func applicationSupport() throws -> StudyLibrary {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return StudyLibrary(root: support.appendingPathComponent("StudyLibrary", isDirectory: true))
  }

  func importDocument(from url: URL, now: Date) async throws -> StudyDocumentSummary {
    let format = try Self.format(of: url)
    let isAccessing = url.startAccessingSecurityScopedResource()
    defer {
      if isAccessing { url.stopAccessingSecurityScopedResource() }
    }

    let fallbackTitle = url.deletingPathExtension().lastPathComponent
    let extraction: StudyExtraction
    switch format {
    case .pdf:
      extraction = try PDFStudyExtractor().extract(fileAt: url, fallbackTitle: fallbackTitle)
    case .epub:
      extraction = try await EPUBStudyExtractor().extract(fileAt: url, fallbackTitle: fallbackTitle)
    }

    let id = UUID()
    let index = StudyIndexer.index(extraction, id: id, importedAt: now)
    let folder = try prepareFolder(for: id)
    // documents() only lists folders with a summary, so a half-written import would keep a
    // private copy of the book that nothing shows or deletes.
    do {
      try fileManager.copyItem(
        at: url, to: folder.appendingPathComponent("source.\(format.rawValue)"))
      try write(index, to: folder.appendingPathComponent(Self.indexFileName))
      try write(index.summary, to: folder.appendingPathComponent(Self.summaryFileName))
    } catch {
      try fileManager.removeItem(at: folder)
      throw error
    }
    return index.summary
  }

  func documents() throws -> [StudyDocumentSummary] {
    guard fileManager.fileExists(atPath: root.path) else { return [] }
    let folders = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    let summaries = try folders.compactMap { folder -> StudyDocumentSummary? in
      let summaryURL = folder.appendingPathComponent(Self.summaryFileName)
      guard fileManager.fileExists(atPath: summaryURL.path) else { return nil }
      return try JSONDecoder().decode(StudyDocumentSummary.self, from: Data(contentsOf: summaryURL))
    }
    return summaries.sorted { $0.importedAt > $1.importedAt }
  }

  func index(for id: UUID) throws -> StudyDocumentIndex {
    let url = folder(for: id).appendingPathComponent(Self.indexFileName)
    return try JSONDecoder().decode(StudyDocumentIndex.self, from: Data(contentsOf: url))
  }

  func delete(id: UUID) throws {
    try fileManager.removeItem(at: folder(for: id))
  }

  var rememberedSubject: StudySubject? {
    get {
      guard let title = defaults.string(forKey: Self.rememberedTitleKey) else { return nil }
      return StudySubject(
        title: title, author: defaults.string(forKey: Self.rememberedAuthorKey), position: "")
    }
    set {
      defaults.set(newValue?.title, forKey: Self.rememberedTitleKey)
      defaults.set(newValue?.author, forKey: Self.rememberedAuthorKey)
    }
  }

  private static func format(of url: URL) throws -> StudyDocumentFormat {
    switch url.pathExtension.lowercased() {
    case "pdf": return .pdf
    case "epub": return .epub
    default: throw StudyImportError.unsupportedFormat
    }
  }

  private func folder(for id: UUID) -> URL {
    root.appendingPathComponent(id.uuidString, isDirectory: true)
  }

  private func prepareFolder(for id: UUID) throws -> URL {
    let protection: [FileAttributeKey: Any] = [
      .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
    ]
    try fileManager.createDirectory(
      at: root, withIntermediateDirectories: true, attributes: protection)
    var backupValues = URLResourceValues()
    backupValues.isExcludedFromBackup = true
    var excludedRoot = root
    try excludedRoot.setResourceValues(backupValues)

    let folder = folder(for: id)
    try fileManager.createDirectory(
      at: folder, withIntermediateDirectories: false, attributes: protection)
    return folder
  }

  private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
    let data = try JSONEncoder().encode(value)
    try data.write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}
