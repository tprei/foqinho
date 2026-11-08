import UIKit
import XCTest

@testable import foqos

private final class CopyRefusingFileManager: FileManager {
  struct CopyRefused: Error {}

  override func copyItem(at srcURL: URL, to dstURL: URL) throws {
    throw CopyRefused()
  }
}

final class StudyLibraryTests: XCTestCase {
  private var root: URL!
  private var defaults: UserDefaults!
  private var defaultsSuite: String!
  private var library: StudyLibrary!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "StudyLibraryTests-\(UUID().uuidString)", isDirectory: true)
    defaultsSuite = "StudyLibraryTests-\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
    library = StudyLibrary(root: root, defaults: defaults)
  }

  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: root.path) {
      try FileManager.default.removeItem(at: root)
    }
    defaults.removePersistentDomain(forName: defaultsSuite)
  }

  private func fixture(_ name: String) throws -> URL {
    try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "epub"))
  }

  private func makePDF(pages: [String]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "study-\(UUID().uuidString).pdf")
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
      for text in pages {
        context.beginPage()
        (text as NSString).draw(
          in: bounds.insetBy(dx: 48, dy: 48),
          withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
        )
      }
    }
    try data.write(to: url)
    addTeardownBlock { try FileManager.default.removeItem(at: url) }
    return url
  }

  private func paragraph(_ topic: String) -> String {
    (1...6).map { "Sentence \($0) explains how \(topic) works in the cell." }.joined(separator: " ")
  }

  func testPdfImportIndexesEachPageWithItsLocator() async throws {
    let url = try makePDF(pages: [paragraph("energy"), paragraph("ATP"), paragraph("oxygen")])

    let summary = try await library.importDocument(from: url, now: Date(timeIntervalSince1970: 10))
    let index = try library.index(for: summary.id)

    XCTAssertEqual(summary.format, .pdf)
    XCTAssertEqual(summary.pageCount, 3)
    XCTAssertEqual(index.passages.map(\.locator), [.pdfPage(1), .pdfPage(2), .pdfPage(3)])
    XCTAssertTrue(index.passages[1].text.contains("ATP"))
  }

  func testPdfWithoutTextIsRefused() async throws {
    let url = try makePDF(pages: ["", "", ""])

    do {
      _ = try await library.importDocument(from: url, now: Date())
      XCTFail("Expected noText")
    } catch {
      XCTAssertEqual(error as? StudyImportError, .noText)
    }
    XCTAssertEqual(try library.documents(), [])
  }

  func testEpubImportKeepsChaptersAndLocators() async throws {
    let summary = try await library.importDocument(
      from: try fixture("study-two-chapters"), now: Date(timeIntervalSince1970: 10))
    let index = try library.index(for: summary.id)

    XCTAssertEqual(summary.title, "Livro de Teste")
    XCTAssertEqual(summary.author, "Ana Lima")
    XCTAssertEqual(index.chapters.map(\.title), ["Capítulo 1: Origem", "Capítulo 2: Método"])
    let labels = Set(index.passages.map(\.locator.label))
    XCTAssertEqual(labels, ["ch. 1: Capítulo 1: Origem", "ch. 2: Capítulo 2: Método"])
    XCTAssertTrue(index.passages.contains { $0.text.contains("mitocôndrias produzem ATP") })
  }

  func testEncryptedEpubIsRefusedAsProtected() async throws {
    do {
      _ = try await library.importDocument(from: try fixture("study-encrypted"), now: Date())
      XCTFail("Expected protected")
    } catch {
      XCTAssertEqual(error as? StudyImportError, .protected)
    }
  }

  func testOtherFormatsAreRefused() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
    try Data("texto".utf8).write(to: url)
    addTeardownBlock { try FileManager.default.removeItem(at: url) }

    do {
      _ = try await library.importDocument(from: url, now: Date())
      XCTFail("Expected unsupportedFormat")
    } catch {
      XCTAssertEqual(error as? StudyImportError, .unsupportedFormat)
    }
  }

  func testFailedImportLeavesNoCopyOfTheBookBehind() async throws {
    let failing = StudyLibrary(
      root: root, defaults: defaults, fileManager: CopyRefusingFileManager())

    do {
      _ = try await failing.importDocument(from: try fixture("study-two-chapters"), now: Date())
      XCTFail("Expected the copy to fail")
    } catch {
      XCTAssertTrue(error is CopyRefusingFileManager.CopyRefused)
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
  }

  func testDocumentsAreNewestFirstAndDeleteRemovesThem() async throws {
    let older = try await library.importDocument(
      from: try fixture("study-two-chapters"), now: Date(timeIntervalSince1970: 10))
    let newer = try await library.importDocument(
      from: try makePDF(pages: [paragraph("energy")]), now: Date(timeIntervalSince1970: 20))

    XCTAssertEqual(try library.documents().map(\.id), [newer.id, older.id])

    try library.delete(id: newer.id)

    XCTAssertEqual(try library.documents().map(\.id), [older.id])
    XCTAssertThrowsError(try library.index(for: newer.id))
  }

  func testRememberedBookKeepsTitleAndAuthor() {
    XCTAssertNil(library.rememberedSubject)

    library.rememberedSubject = StudySubject(
      title: "Dom Casmurro", author: "Machado de Assis", position: "cap. 10")

    XCTAssertEqual(
      StudyLibrary(root: root, defaults: defaults).rememberedSubject,
      StudySubject(title: "Dom Casmurro", author: "Machado de Assis", position: "")
    )
  }
}
