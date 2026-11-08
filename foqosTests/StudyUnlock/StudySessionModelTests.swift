import XCTest

@testable import foqos

private final class FakeSpeaker: StudySpeaker {
  private(set) var lines: [String] = []

  func speak(_ text: String, language: StudyLanguage) async {
    lines.append(text)
  }

  func stopSpeaking() {}
}

private final class FakeListener: StudyListener {
  var transcripts: [Result<String, StudyListenerError>] = []
  var holdsPrepare = false
  var prepareError: StudyListenerError?
  private(set) var startCount = 0
  private var heldPrepare: CheckedContinuation<Void, Never>?

  var isHoldingPrepare: Bool { heldPrepare != nil }

  func prepare(language: StudyLanguage, allowServer: Bool) async throws -> StudyListeningRoute {
    if holdsPrepare {
      await withCheckedContinuation { heldPrepare = $0 }
    }
    if let prepareError { throw prepareError }
    return .onDevice
  }

  func releasePrepare() {
    heldPrepare?.resume()
    heldPrepare = nil
  }

  func startListening(language: StudyLanguage, allowServer: Bool) async throws {
    startCount += 1
  }

  func finishListening() async throws -> String {
    try transcripts.removeFirst().get()
  }

  func cancelListening() {}
}

private final class FakeProvider: StudyModelProvider {
  var host = "api.example.com"
  var replies: [Result<StudyEvaluationPayload, StudyProviderError>] = []
  var holdsReplies = false
  private(set) var requests: [StudyEvaluationRequest] = []
  private var heldReply: CheckedContinuation<Void, Never>?

  var isHoldingReply: Bool { heldReply != nil }

  func evaluate(_ request: StudyEvaluationRequest) async throws -> StudyEvaluationPayload {
    requests.append(request)
    if holdsReplies {
      await withCheckedContinuation { heldReply = $0 }
    }
    return try replies.removeFirst().get()
  }

  func releaseReply() {
    heldReply?.resume()
    heldReply = nil
  }
}

@MainActor
final class StudySessionModelTests: XCTestCase {
  private let noon = Date(timeIntervalSince1970: 1_800_000_000)
  private let speaker = FakeSpeaker()
  private let listener = FakeListener()
  private var provider = FakeProvider()
  private var language: StudyLanguage = .portugueseBrazil
  private var approvals: [StudyApproval] = []
  private var unlockError: Error?
  private var consentedHosts: Set<String> = ["api.example.com"]
  private var providerSetupError: StudyProviderError?
  private var remembered: [StudySubject] = []

  private let document = StudyDocumentSummary(
    id: UUID(),
    title: "Biologia",
    author: "Ana Lima",
    format: .pdf,
    importedAt: Date(timeIntervalSince1970: 0),
    pageCount: 3,
    passageCount: 3
  )

  private var index: StudyDocumentIndex {
    StudyDocumentIndex(summary: document, chapters: [], passages: StudyDomainFixtures.passages)
  }

  private func makeModel() -> StudySessionModel {
    StudySessionModel(
      dependencies: StudySessionDependencies(
        speaker: speaker,
        listener: listener,
        currentLanguage: { self.language },
        loadIndex: { _ in self.index },
        rememberSubject: { self.remembered.append($0) },
        makeProvider: {
          if let error = self.providerSetupError { throw error }
          return self.provider
        },
        hasProviderConsent: { self.consentedHosts.contains($0) },
        recordProviderConsent: { _ = self.consentedHosts.insert($0) },
        allowsServerSpeech: { false },
        recordServerSpeechConsent: {},
        unlock: { approval in
          if let error = self.unlockError { throw error }
          self.approvals.append(approval)
          return StudyUnlockGrant(
            id: UUID(), sessionId: "s", profileId: UUID(), createdAt: self.noon,
            expiresAt: self.noon.addingTimeInterval(20 * 60), mode: approval.mode,
            coveredConceptCount: approval.coveredConceptCount,
            evidenceLocators: approval.evidenceLocators.map(\.label),
            followUpCount: approval.followUpCount)
        },
        now: { self.noon }
      )
    )
  }

  private func say(_ transcript: String, to model: StudySessionModel) async {
    listener.transcripts.append(.success(transcript))
    await model.toggleListening()
    await model.toggleListening()
  }

  private func reachEvaluation(_ model: StudySessionModel) async {
    await model.begin(with: .document(document))
    await say("páginas 40 a 41", to: model)
    await say("A mitocôndria produz ATP para a célula.", to: model)
  }

  private func pass(confidence: Double = 0.9) -> StudyEvaluationPayload {
    StudyDomainFixtures.payload(confidence: confidence, nextQuestion: "E o oxigênio?")
  }

  func testPassingDocumentConversationUnlocksOnce() async throws {
    provider.replies = [.success(pass())]
    let model = makeModel()

    await reachEvaluation(model)

    XCTAssertEqual(approvals.count, 1)
    XCTAssertEqual(approvals.first?.evidenceLocators, [.pdfPage(41)])
    XCTAssertEqual(model.grant?.mode, .document)
    XCTAssertNil(model.failure)
    XCTAssertEqual(speaker.lines.first?.hasPrefix("Modo documento"), true)
    XCTAssertEqual(
      speaker.lines.last, "Você explicou bem a origem do ATP. Liberado por 20 minutos.")
    XCTAssertEqual(provider.requests.first?.subject.position, "pp. 40–41")
  }

  func testBrokenReplyNeverUnlocksAndRetrySendsTheSameRequest() async throws {
    let failures: [StudyProviderError] = [.malformedResponse, .timedOut, .offline, .refused]
    for error in failures {
      provider.replies = [.failure(error)]
      let model = makeModel()

      await reachEvaluation(model)

      XCTAssertEqual(model.failure, .evaluationFailed(error))
      XCTAssertEqual(approvals, [])
      XCTAssertNil(model.grant)
    }

    let model = makeModel()
    provider.replies = [.failure(.offline), .success(pass())]
    await reachEvaluation(model)
    await model.retry()

    XCTAssertEqual(approvals.count, 1)
    let requests = provider.requests.suffix(2)
    XCTAssertEqual(requests.first, requests.last)
  }

  func testEvidenceThatWasNotSentIsAnInvalidEvaluation() async {
    let forged = StudyDomainFixtures.payload(
      evidence: [StudyEvaluationPayload.Evidence(chunkId: "p99.9", locator: "p. 99", concept: "x")])
    provider.replies = [.success(forged)]
    let model = makeModel()

    await reachEvaluation(model)

    XCTAssertEqual(model.failure, .invalidEvaluation)
    XCTAssertEqual(approvals, [])
  }

  func testLowConfidenceAsksAFollowUpThatReachesTheNextRequest() async throws {
    provider.replies = [.success(pass(confidence: 0.3)), .success(pass())]
    let model = makeModel()

    await reachEvaluation(model)

    XCTAssertEqual(approvals, [])
    XCTAssertEqual(model.conversation?.phase, .answering(question: "E o oxigênio?"))
    XCTAssertEqual(speaker.lines.last, "Você explicou bem a origem do ATP. E o oxigênio?")

    await say("O oxigênio recebe os elétrons no fim.", to: model)

    let second = try XCTUnwrap(provider.requests.last)
    XCTAssertEqual(second.followUpsRemaining, 1)
    XCTAssertEqual(
      second.turns.last,
      .followUp(question: "E o oxigênio?", answer: "O oxigênio recebe os elétrons no fim."))
    XCTAssertEqual(approvals.first?.followUpCount, 1)
  }

  func testNothingHeardCostsNothingAndRetryListensAgain() async {
    let model = makeModel()
    await model.begin(with: .document(document))
    await say("página 40", to: model)

    listener.transcripts.append(.failure(.nothingHeard))
    await model.toggleListening()
    await model.toggleListening()

    XCTAssertEqual(model.failure, .nothingHeard)
    XCTAssertEqual(model.conversation?.phase, .explaining)
    XCTAssertEqual(model.conversation?.followUpsAsked, 0)
    XCTAssertEqual(provider.requests, [])

    let starts = listener.startCount
    await model.retry()
    XCTAssertEqual(listener.startCount, starts + 1)
    XCTAssertEqual(model.activity, .listening(since: noon))
  }

  func testUnlockFailureIsReportedAndNothingIsGranted() async {
    provider.replies = [.success(pass())]
    unlockError = StudyUnlockError.pauseActive
    let model = makeModel()

    await reachEvaluation(model)

    XCTAssertEqual(model.failure, .unlockFailed(StudyUnlockError.pauseActive.localizedDescription))
    XCTAssertNil(model.grant)
  }

  func testMissingSetupFailsBeforeAnythingIsSaid() async {
    providerSetupError = .notConfigured
    let model = makeModel()

    await model.begin(with: .modelKnowledge(remembered: nil))

    XCTAssertEqual(model.failure, .providerNotConfigured)
    XCTAssertNil(model.conversation)
    XCTAssertEqual(speaker.lines, [])

    providerSetupError = .missingCredential
    await model.begin(with: .modelKnowledge(remembered: nil))
    XCTAssertEqual(model.failure, .missingCredential)
  }

  func testNoProviderCallUntilTheHostIsConsented() async {
    consentedHosts = []
    provider.replies = [.success(pass())]
    let model = makeModel()

    await reachEvaluation(model)

    XCTAssertEqual(model.failure, .needsProviderConsent(host: "api.example.com"))
    XCTAssertEqual(provider.requests, [])

    await model.acceptConsent()

    XCTAssertEqual(provider.requests.count, 1)
    XCTAssertEqual(approvals.count, 1)
  }

  func testModelKnowledgeConversationRemembersTheBook() async {
    let payload = StudyDomainFixtures.payload(basis: "model_knowledge", evidence: [])
    provider.replies = [.success(payload)]
    let model = makeModel()

    await model.begin(with: .modelKnowledge(remembered: nil))
    await say("Dom Casmurro", to: model)
    await say("Machado de Assis", to: model)
    await say("capítulo 10", to: model)
    await say("Bentinho desconfia de Capitu.", to: model)

    XCTAssertEqual(
      remembered,
      [StudySubject(title: "Dom Casmurro", author: "Machado de Assis", position: "capítulo 10")])
    XCTAssertEqual(provider.requests.first?.passages, [])
    XCTAssertEqual(approvals.first?.mode, .modelKnowledge)
  }

  func testClosingWhileTheModelThinksNeverUnlocks() async throws {
    provider.replies = [.success(pass())]
    provider.holdsReplies = true
    let model = makeModel()
    await model.begin(with: .document(document))
    await say("páginas 40 a 41", to: model)
    listener.transcripts.append(.success("A mitocôndria produz ATP para a célula."))
    await model.toggleListening()

    let finishing = Task { await model.toggleListening() }
    var waits = 0
    while !provider.isHoldingReply && waits < 1_000 {
      await Task.yield()
      waits += 1
    }
    XCTAssertTrue(provider.isHoldingReply)

    model.close()
    provider.releaseReply()
    await finishing.value

    XCTAssertEqual(approvals, [])
    XCTAssertNil(model.grant)
    XCTAssertNil(model.conversation)
    XCTAssertNil(model.failure)
    XCTAssertEqual(model.activity, .idle)
  }

  func testASecondTalkWhilePreparingStartsNothing() async {
    let model = makeModel()
    await model.begin(with: .document(document))
    listener.holdsPrepare = true

    let first = Task { await model.toggleListening() }
    var waits = 0
    while !listener.isHoldingPrepare && waits < 1_000 {
      await Task.yield()
      waits += 1
    }
    XCTAssertEqual(model.activity, .preparing)

    await model.toggleListening()
    listener.releasePrepare()
    await first.value

    XCTAssertEqual(listener.startCount, 1)
    XCTAssertEqual(model.activity, .listening(since: noon))
  }

  func testFixingTheKeyInSettingsSendsTheSameAnswerThroughTheNewProvider() async {
    provider.replies = [.failure(.httpStatus(401))]
    let model = makeModel()
    await reachEvaluation(model)
    XCTAssertEqual(model.failure, .evaluationFailed(.httpStatus(401)))
    let rejected = provider

    providerSetupError = .missingCredential
    model.settingsDidChange()
    XCTAssertEqual(model.failure, .missingCredential)

    providerSetupError = nil
    provider = FakeProvider()
    provider.replies = [.success(pass())]
    model.settingsDidChange()
    XCTAssertEqual(model.failure, .settingsChanged)
    await model.retry()

    XCTAssertEqual(rejected.requests.count, 1)
    XCTAssertEqual(provider.requests, rejected.requests)
    XCTAssertEqual(approvals.count, 1)
  }

  func testConsentBelongsToTheHostTheConversationGoesTo() async {
    provider.host = "openrouter.ai"
    provider.replies = [.success(pass())]
    let model = makeModel()

    await reachEvaluation(model)

    XCTAssertEqual(model.failure, .needsProviderConsent(host: "openrouter.ai"))
    XCTAssertEqual(provider.requests, [])
    await model.acceptConsent()
    XCTAssertEqual(consentedHosts, ["api.example.com", "openrouter.ai"])
    XCTAssertEqual(approvals.count, 1)
  }

  func testChangingTheHostInSettingsSendsOnlyWithConsentForTheNewHost() async {
    provider.host = "openrouter.ai"
    provider.replies = [.success(pass())]
    let model = makeModel()
    await reachEvaluation(model)
    XCTAssertEqual(model.failure, .needsProviderConsent(host: "openrouter.ai"))

    let replacement = FakeProvider()
    replacement.replies = [.success(pass())]
    provider = replacement
    model.settingsDidChange()
    await model.retry()

    XCTAssertEqual(consentedHosts, ["api.example.com"])
    XCTAssertEqual(replacement.requests.count, 1)
    XCTAssertEqual(approvals.count, 1)
  }

  func testChangingTheLanguageAfterItWasUnavailableStartsOverInTheNewLanguage() async {
    let model = makeModel()
    await model.begin(with: .document(document))
    listener.prepareError = .languageUnsupported
    await model.toggleListening()
    XCTAssertEqual(model.failure, .languageUnavailable)

    listener.prepareError = nil
    language = .englishUS
    model.settingsDidChange()
    XCTAssertEqual(model.failure, .settingsChanged)
    await model.retry()

    XCTAssertNil(model.failure)
    XCTAssertEqual(model.conversation?.language, .englishUS)
    XCTAssertEqual(listener.startCount, 0)
  }
}
