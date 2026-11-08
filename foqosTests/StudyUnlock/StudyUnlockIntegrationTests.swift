import DeviceActivity
import SwiftData
import XCTest

@testable import foqos

@MainActor
final class StudyUnlockIntegrationTests: XCTestCase {
  private struct Scheduled: Equatable {
    let profileId: UUID
    let end: Date
    let now: Date
  }

  private struct SchedulerUnavailable: Error {}
  private struct FixtureNotApproved: Error {}

  private var scheduled: [Scheduled] = []

  override func setUp() {
    super.setUp()
    SharedData.flushActiveSession()
    StudyUnlockGrantStore.clearAll()
    scheduled = []
  }

  override func tearDown() {
    SharedData.flushActiveSession()
    StudyUnlockGrantStore.clearAll()
    super.tearDown()
  }

  private var noon: Date {
    Calendar.current.date(
      from: DateComponents(year: 2026, month: 11, day: 9, hour: 12, minute: 0, second: 0))!
  }

  private func approval() throws -> StudyApproval {
    let request = StudyDomainFixtures.request()
    let step = StudyDecision.next(
      after: StudyDomainFixtures.evaluation(),
      request: request,
      followUpsAsked: 1,
      decidedAt: noon
    )
    guard case .approve(let approval, _) = step else {
      throw FixtureNotApproved()
    }
    return approval
  }

  private func makeContext() throws -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: BlockedProfileSession.self, BlockedProfiles.self, configurations: configuration)
    return ModelContext(container)
  }

  private func makeSession(
    strategyId: String = NFCBlockingStrategy.id,
    enableStudyUnlock: Bool = true,
    minutes: Int = 20,
    context: ModelContext
  ) throws -> BlockedProfileSession {
    let profile = BlockedProfiles(
      name: "Focus",
      blockingStrategyId: strategyId,
      enableBreaks: true,
      enableStudyUnlock: enableStudyUnlock,
      studyUnlockMinutes: minutes
    )
    context.insert(profile)
    let session = BlockedProfileSession.createSession(
      in: context, withTag: strategyId, withProfile: profile)
    try context.save()
    return session
  }

  private func unlock(
    _ context: ModelContext,
    sessionId: String,
    now: Date? = nil,
    failScheduling: Bool = false
  ) throws -> StudyUnlockGrant {
    try StrategyManager().startStudyUnlock(
      context: context,
      approval: try approval(),
      sessionId: sessionId,
      now: now ?? noon,
      schedulePause: { profile, end, now in
        if failScheduling { throw SchedulerUnavailable() }
        self.scheduled.append(Scheduled(profileId: profile.id, end: end, now: now))
      }
    )
  }

  private func assertRefused(
    _ expected: StudyUnlockError,
    context: ModelContext,
    sessionId: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try unlock(context, sessionId: sessionId), file: file, line: line) {
      XCTAssertEqual($0 as? StudyUnlockError, expected, file: file, line: line)
    }
    XCTAssertEqual(scheduled, [], file: file, line: line)
    XCTAssertEqual(StudyUnlockGrantStore.grants(), [], file: file, line: line)
  }

  func testApprovedStudyPausesThroughTheExactExpiryAndRecordsTheGrant() throws {
    let context = try makeContext()
    let session = try makeSession(minutes: 20, context: context)

    let grant = try unlock(context, sessionId: session.id)

    let expiry = noon.addingTimeInterval(20 * 60)
    XCTAssertEqual(
      scheduled, [Scheduled(profileId: session.blockedProfile.id, end: expiry, now: noon)])
    XCTAssertEqual(grant.sessionId, session.id)
    XCTAssertEqual(grant.createdAt, noon)
    XCTAssertEqual(grant.expiresAt, expiry)
    XCTAssertEqual(grant.mode, .document)
    XCTAssertEqual(grant.evidenceLocators, ["p. 41"])
    XCTAssertEqual(grant.followUpCount, 1)
    XCTAssertEqual(StudyUnlockGrantStore.grants(), [grant])
  }

  func testApprovalNearMidnightStillGetsTheFullDuration() throws {
    let context = try makeContext()
    let session = try makeSession(minutes: 15, context: context)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let lateNight = try XCTUnwrap(
      calendar.date(
        from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 55, second: 0)))

    let grant = try unlock(context, sessionId: session.id, now: lateNight)
    let schedule = OneShotDeviceActivitySchedule.make(
      endingAt: grant.expiresAt, now: lateNight, calendar: calendar)

    XCTAssertEqual(grant.expiresAt, lateNight.addingTimeInterval(15 * 60))
    XCTAssertEqual(schedule.intervalEnd.year, 2026)
    XCTAssertEqual(schedule.intervalEnd.month, 11)
    XCTAssertEqual(schedule.intervalEnd.day, 9)
    XCTAssertEqual(schedule.intervalEnd.hour, 0)
    XCTAssertEqual(schedule.intervalEnd.minute, 10)
    XCTAssertEqual(schedule.intervalEnd.second, 0)
    XCTAssertEqual(schedule.intervalStart.day, 8)
    XCTAssertEqual(schedule.intervalStart.hour, 23)
    XCTAssertEqual(schedule.intervalStart.minute, 54)
    XCTAssertFalse(schedule.repeats)
  }

  func testShortApprovalJustAfterMidnightStillMeetsTheMinimumInterval() throws {
    let context = try makeContext()
    let session = try makeSession(minutes: 5, context: context)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let earlyMorning = try XCTUnwrap(
      calendar.date(
        from: DateComponents(year: 2026, month: 11, day: 9, hour: 0, minute: 3, second: 0)))

    let grant = try unlock(context, sessionId: session.id, now: earlyMorning)
    let schedule = OneShotDeviceActivitySchedule.make(
      endingAt: grant.expiresAt, now: earlyMorning, calendar: calendar)

    let start = try XCTUnwrap(calendar.date(from: schedule.intervalStart))
    let end = try XCTUnwrap(calendar.date(from: schedule.intervalEnd))
    XCTAssertEqual(end, earlyMorning.addingTimeInterval(5 * 60))
    XCTAssertGreaterThanOrEqual(end.timeIntervalSince(start), 15 * 60)
    XCTAssertLessThan(start, earlyMorning)
    XCTAssertEqual(schedule.intervalStart.day, 8)
  }

  func testOneShotScheduleKeepsTheSoftUnblockLeadTime() {
    let calendar = Calendar.current
    let schedule = OneShotDeviceActivitySchedule.make(
      endingAt: noon.addingTimeInterval(10), now: noon, calendar: calendar)

    XCTAssertEqual(
      calendar.date(from: schedule.intervalEnd),
      noon.addingTimeInterval(OneShotDeviceActivitySchedule.minimumLeadTime)
    )
  }

  func testUnlockIsRefusedWithoutAMatchingEligibleSession() throws {
    let context = try makeContext()
    assertRefused(.noActiveSession, context: context, sessionId: "none")

    let session = try makeSession(context: context)
    assertRefused(.sessionChanged, context: context, sessionId: "another-session")

    session.blockedProfile.enableStudyUnlock = false
    assertRefused(.disabled(profileName: "Focus"), context: context, sessionId: session.id)

    session.blockedProfile.enableStudyUnlock = true
    session.startBreak()
    assertRefused(.breakActive, context: context, sessionId: session.id)
  }

  func testUnlockIsRefusedDuringAPause() throws {
    let context = try makeContext()
    let session = try makeSession(context: context)
    session.startPause()
    try context.save()

    assertRefused(.pauseActive, context: context, sessionId: session.id)
  }

  func testTemporaryAccessProfilesNeverGetAStudyPause() throws {
    let context = try makeContext()
    let session = try makeSession(
      strategyId: NFCSoftUnblockBlockingStrategy.id, enableStudyUnlock: true, context: context)

    assertRefused(
      .unsupportedStrategy(profileName: "Focus"), context: context, sessionId: session.id)
  }

  func testSchedulingFailureLeavesNoGrant() throws {
    let context = try makeContext()
    let session = try makeSession(context: context)

    XCTAssertThrowsError(try unlock(context, sessionId: session.id, failScheduling: true)) {
      guard case .schedulingFailed = $0 as? StudyUnlockError else {
        return XCTFail("Expected schedulingFailed, got \($0)")
      }
    }
    XCTAssertEqual(StudyUnlockGrantStore.grants(), [])
  }

  func testPauseCountdownFollowsTheGrantThatCoversIt() throws {
    let context = try makeContext()
    let session = try makeSession(context: context)
    let grant = StudyUnlockGrant(
      id: UUID(),
      sessionId: session.id,
      profileId: session.blockedProfile.id,
      createdAt: noon,
      expiresAt: noon.addingTimeInterval(20 * 60),
      mode: .modelKnowledge,
      coveredConceptCount: 2,
      evidenceLocators: [],
      followUpCount: 0
    )
    try StudyUnlockGrantStore.record(grant)

    session.pauseStartTime = noon.addingTimeInterval(2)
    XCTAssertEqual(SessionTimeCalculator.breakOrPauseEndTime(for: session), grant.expiresAt)

    let laterPause = noon.addingTimeInterval(30 * 60)
    session.pauseStartTime = laterPause
    let strategyPause = StrategyPauseTimerData.toStrategyPauseTimerData(from: nil)
    XCTAssertEqual(
      SessionTimeCalculator.breakOrPauseEndTime(for: session),
      laterPause.addingTimeInterval(TimeInterval(strategyPause.pauseDurationInMinutes * 60))
    )
  }

  func testOpeningTheAppEndsAStudyPauseWhoseTimeIsUp() throws {
    let context = try makeContext()
    let session = try makeSession(context: context)
    let createdAt = Date().addingTimeInterval(-30 * 60)
    try StudyUnlockGrantStore.record(
      StudyUnlockGrant(
        id: UUID(), sessionId: session.id, profileId: session.blockedProfile.id,
        createdAt: createdAt, expiresAt: createdAt.addingTimeInterval(20 * 60),
        mode: .document, coveredConceptCount: 1, evidenceLocators: ["p. 41"], followUpCount: 0))
    let pauseStart = createdAt.addingTimeInterval(2)
    SharedData.setPauseStartTime(date: pauseStart)
    session.pauseStartTime = pauseStart
    try context.save()
    XCTAssertFalse(SessionTimeCalculator.isCountdownExpired(for: session))

    StrategyManager().loadActiveSession(context: context)

    XCTAssertFalse(session.isPauseActive)
    XCTAssertNotNil(session.pauseEndTime)
  }

  func testOpeningTheAppKeepsAStudyPauseThatIsStillRunning() throws {
    let context = try makeContext()
    let session = try makeSession(context: context)
    let createdAt = Date().addingTimeInterval(-60)
    try StudyUnlockGrantStore.record(
      StudyUnlockGrant(
        id: UUID(), sessionId: session.id, profileId: session.blockedProfile.id,
        createdAt: createdAt, expiresAt: createdAt.addingTimeInterval(20 * 60),
        mode: .modelKnowledge, coveredConceptCount: 1, evidenceLocators: [], followUpCount: 0))
    SharedData.setPauseStartTime(date: createdAt.addingTimeInterval(2))
    session.pauseStartTime = createdAt.addingTimeInterval(2)
    try context.save()

    StrategyManager().loadActiveSession(context: context)

    XCTAssertTrue(session.isPauseActive)
  }

  func testDraftDropsStudyUnlockForTemporaryAccess() {
    let draft = BlockedProfileDraft()
    draft.enableStudyUnlock = true

    draft.selectedStrategy = NFCSoftUnblockBlockingStrategy()

    XCTAssertFalse(draft.selectedStrategyAllowsStudyUnlock)
    XCTAssertFalse(draft.enableStudyUnlock)
  }
}
