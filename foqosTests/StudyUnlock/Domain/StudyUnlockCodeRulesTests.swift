import Foundation
import XCTest

// The study unlock rules that the compiler and swift-format can't check.
final class StudyUnlockCodeRulesTests: XCTestCase {
  static let featureFilesOutsideFolder = ["Foqos/Utils/StudyUnlockGrantStore.swift"]

  // Built from parts so the rules don't depend on how this file is written.
  private static let domainBans = [
    "Date" + "()", "User" + "Defaults", "File" + "Manager", "URL" + "Session",
  ]
  private static let featureBans = [
    "print" + "(", "debug" + "Print(", "dump" + "(", "Log" + "ger", "os" + "_log", "NS" + "Log",
    "try" + "!", "AVAudio" + "Recorder", "AVAudioFile(" + "forWriting", "swift-format" + "-ignore",
  ]
  // Audio only ever lives in memory, so voice code has no reason to touch a file at all.
  private static let voiceBans = [
    "File" + "Manager", "File" + "Handle", ".write(" + "to:", "Output" + "Stream",
    "AVAudio" + "File", "ExtAudio" + "File", "AVAsset" + "Writer",
  ]
  private struct SourcesNotFound: Error {}

  func testDomainImportsOnlyFoundationAndReadsNoClockOrIO() throws {
    let root = try Self.repositoryRoot()
    let files = try Self.swiftFiles(in: root.appendingPathComponent("Foqos/StudyUnlock/Domain"))
    let nowMember = try NSRegularExpression(pattern: "\\." + "now\\b")
    XCTAssertFalse(files.isEmpty)

    for file in files {
      for (number, line) in try Self.lines(of: file) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("import ") {
          XCTAssertEqual(trimmed, "import Foundation", "\(file.lastPathComponent):\(number)")
        }
        for banned in Self.domainBans where line.contains(banned) {
          XCTFail("\(file.lastPathComponent):\(number) uses \(banned)")
        }
        let range = NSRange(line.startIndex..., in: line)
        if nowMember.firstMatch(in: line, range: range) != nil {
          XCTFail("\(file.lastPathComponent):\(number) reads the clock")
        }
      }
    }
  }

  func testFeatureNeverLogsOrWritesAudio() throws {
    let root = try Self.repositoryRoot()
    let folderFiles = try Self.swiftFiles(in: root.appendingPathComponent("Foqos/StudyUnlock"))
    let otherFiles = Self.featureFilesOutsideFolder.map { root.appendingPathComponent($0) }

    for file in folderFiles + otherFiles {
      for (number, line) in try Self.lines(of: file) {
        for banned in Self.featureBans where line.contains(banned) {
          XCTFail("\(file.path):\(number) uses \(banned)")
        }
      }
    }
  }

  func testVoiceNeverTouchesFiles() throws {
    let root = try Self.repositoryRoot()
    let files = try Self.swiftFiles(in: root.appendingPathComponent("Foqos/StudyUnlock/Voice"))
    XCTAssertFalse(files.isEmpty)

    for file in files {
      for (number, line) in try Self.lines(of: file) {
        for banned in Self.voiceBans where line.contains(banned) {
          XCTFail("\(file.lastPathComponent):\(number) uses \(banned)")
        }
      }
    }
  }

  private static func repositoryRoot() throws -> URL {
    var folder = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
      .deletingLastPathComponent()
    while folder.path != "/" {
      let feature = folder.appendingPathComponent("Foqos/StudyUnlock")
      if FileManager.default.fileExists(atPath: feature.path) { return folder }
      folder.deleteLastPathComponent()
    }
    throw SourcesNotFound()
  }

  private static func swiftFiles(in folder: URL) throws -> [URL] {
    let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
    let urls = (enumerator?.allObjects ?? []).compactMap { $0 as? URL }
    return urls.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
  }

  private static func lines(of file: URL) throws -> [(Int, String)] {
    let source = try String(contentsOf: file, encoding: .utf8)
    return source.components(separatedBy: "\n").enumerated().map { ($0.offset + 1, $0.element) }
  }
}
