import Foundation

enum StudyPreviewData {
  static let end = Date(timeIntervalSince1970: 1_794_148_320)

  static let document = StudyDocumentSummary(
    id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
    title: "Deep Work",
    author: "Cal Newport",
    format: .pdf,
    importedAt: end.addingTimeInterval(-86_400),
    pageCount: 304,
    passageCount: 286
  )

  static let epub = StudyDocumentSummary(
    id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
    title: "The Dispossessed: An Ambiguous Utopia",
    author: "Ursula K. Le Guin",
    format: .epub,
    importedAt: end.addingTimeInterval(-172_800),
    pageCount: nil,
    passageCount: 412
  )

  static let subject = StudySubject(
    title: "Deep Work", author: "Cal Newport", position: "pages 40 to 52")

  static func grant(mode: StudyMode) -> StudyUnlockGrant {
    let identifier: UUID
    if mode == .document {
      identifier = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
    } else {
      identifier = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))
    }
    return StudyUnlockGrant(
      id: identifier,
      sessionId: "preview-session",
      profileId: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5)),
      createdAt: end.addingTimeInterval(-900),
      expiresAt: end,
      mode: mode,
      coveredConceptCount: 3,
      evidenceLocators: mode == .document ? ["p. 42", "p. 46"] : [],
      followUpCount: 1
    )
  }
}
