import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import foqos

// Throwaway, never merged: the "before" captures for the study unlock stack, taken on upstream
// main with the same sizes and data as the "after" captures.
@MainActor
final class StudyUnlockScreenshotDump: XCTestCase {
  private let sizes = [CGSize(width: 375, height: 667), CGSize(width: 393, height: 852), CGSize(width: 430, height: 932)]

  private func dump<V: View>(_ name: String, _ view: V) throws {
    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    for size in sizes {
      let window = UIWindow(windowScene: scene)
      window.frame = CGRect(origin: .zero, size: size)
      window.rootViewController = UIHostingController(
        rootView: view.environmentObject(ThemeManager.shared))
      window.makeKeyAndVisible()
      RunLoop.main.run(until: Date().addingTimeInterval(1.2))
      let format = UIGraphicsImageRendererFormat()
      format.scale = 2
      let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
      let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.55))
      print("STUDYSHOT-BEGIN before-\(name)-\(Int(size.width))")
      print(data.base64EncodedString())
      print("STUDYSHOT-END")
      window.isHidden = true
    }
  }

  func testDumpChangedScreens() throws {
    let container = try ModelContainer(
      for: BlockedProfileSession.self, BlockedProfiles.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    defer { SharedData.flushActiveSession() }

    let draft = BlockedProfileDraft()
    draft.enableBreaks = true
    try dump("profile-form", Form { BlockedProfileBreaksSection(draft: draft, disabled: false) })

    try dump(
      "settings",
      SettingsView()
        .environmentObject(RequestAuthorizer())
        .environmentObject(StrategyManager())
        .modelContainer(container))

    let profile = BlockedProfiles(name: "Deep Work", blockingStrategyId: NFCBlockingStrategy.id)
    context.insert(profile)
    let session = BlockedProfileSession.createSession(
      in: context, withTag: NFCBlockingStrategy.id, withProfile: profile)
    try context.save()
    let manager = StrategyManager()
    manager.activeSession = session
    try dump(
      "active-session",
      ActiveProfileSessionView(
        profile: profile, elapsedTime: 1_500, displayTime: 1_500, isBreakAvailable: false,
        isBreakActive: false, isPauseActive: false, isCountdownExpired: false,
        onBreakTapped: {}, onStopTapped: {}, onExpiredCountdownReset: {}
      )
      .environmentObject(manager)
      .modelContainer(container))
  }
}
