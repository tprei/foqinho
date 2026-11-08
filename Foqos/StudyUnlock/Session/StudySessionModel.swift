import Combine
import Foundation

struct StudySessionDependencies {
  let speaker: StudySpeaker
  let listener: StudyListener
  let currentLanguage: () -> StudyLanguage
  let loadIndex: (UUID) throws -> StudyDocumentIndex
  let rememberSubject: (StudySubject) -> Void
  let makeProvider: () throws -> StudyModelProvider
  let hasProviderConsent: (String) -> Bool
  let recordProviderConsent: (String) throws -> Void
  let allowsServerSpeech: () -> Bool
  let recordServerSpeechConsent: () throws -> Void
  let unlock: (StudyApproval) throws -> StudyUnlockGrant
  let now: () -> Date
}

@MainActor
final class StudySessionModel: ObservableObject {
  enum Activity: Equatable {
    case idle
    case preparing
    case speaking
    case listening(since: Date)
    case transcribing
    case evaluating
  }

  enum Failure: Equatable {
    case providerNotConfigured
    case missingCredential
    case needsProviderConsent(host: String)
    case needsServerSpeechConsent
    case consentNotSaved
    case microphoneDenied
    case speechRecognitionDenied
    case languageUnavailable
    case nothingHeard
    case positionNotUnderstood
    case evaluationFailed(StudyProviderError?)
    case invalidEvaluation
    case documentUnavailable
    case unlockFailed(String)
    case settingsChanged
    case audioUnavailable
  }

  @Published private(set) var conversation: StudyConversation?
  @Published private(set) var activity: Activity = .idle
  @Published private(set) var failure: Failure?
  @Published private(set) var spokenLine: String?
  @Published private(set) var lastTranscript: String?
  @Published private(set) var lastEvaluation: StudyEvaluation?
  @Published private(set) var grant: StudyUnlockGrant?
  @Published private(set) var listeningRoute: StudyListeningRoute?

  private let dependencies: StudySessionDependencies
  private var language: StudyLanguage
  private var phrases: StudyPhrases
  private var index: StudyDocumentIndex?
  private var provider: StudyModelProvider?
  // close() bumps the run, so work that resumes after an await from a closed
  // conversation can't apply its result or unlock anything.
  private var run = 0

  init(dependencies: StudySessionDependencies) {
    self.dependencies = dependencies
    language = dependencies.currentLanguage()
    phrases = StudyPhrases(language: language)
  }

  func begin(with source: StudySource) async {
    close()
    language = dependencies.currentLanguage()
    phrases = StudyPhrases(language: language)
    do {
      provider = try dependencies.makeProvider()
    } catch {
      failure = Self.setupFailure(for: error)
      return
    }

    if case .document(let document) = source {
      do {
        index = try dependencies.loadIndex(document.id)
      } catch {
        failure = .documentUnavailable
        return
      }
    }

    let conversation = StudyConversation(source: source, language: language)
    self.conversation = conversation
    await say(phrases.modeDisclosure(for: source) + " " + prompt(for: conversation))
  }

  func toggleListening() async {
    switch activity {
    case .listening:
      await finishListening()
    case .idle, .speaking:
      await startListening()
    case .preparing, .transcribing, .evaluating:
      return
    }
  }

  func settingsDidChange() {
    guard conversation != nil else {
      if failure == .providerNotConfigured || failure == .missingCredential { failure = nil }
      return
    }
    do {
      provider = try dependencies.makeProvider()
    } catch {
      failure = Self.setupFailure(for: error)
      return
    }
    switch failure {
    case .providerNotConfigured, .missingCredential, .needsProviderConsent, .languageUnavailable,
      .evaluationFailed(.some(.httpStatus(401))), .evaluationFailed(.some(.httpStatus(403))):
      failure = .settingsChanged
    default:
      return
    }
  }

  func retry() async {
    switch failure {
    case .evaluationFailed, .invalidEvaluation:
      failure = nil
      await evaluate()
    case .settingsChanged:
      failure = nil
      if conversation?.language != dependencies.currentLanguage() {
        await restart()
      } else if conversation?.phase == .evaluating {
        await evaluate()
      } else {
        await startListening()
      }
    case .nothingHeard, .positionNotUnderstood, .audioUnavailable:
      failure = nil
      await startListening()
    default:
      return
    }
  }

  func acceptConsent() async {
    switch failure {
    case .needsProviderConsent(let host):
      guard saveConsent({ try dependencies.recordProviderConsent(host) }) else { return }
      await evaluate()
    case .needsServerSpeechConsent:
      guard saveConsent(dependencies.recordServerSpeechConsent) else { return }
      await startListening()
    default:
      return
    }
  }

  func restart() async {
    guard let source = conversation?.source else { return }
    await begin(with: source)
  }

  func close() {
    run += 1
    dependencies.speaker.stopSpeaking()
    dependencies.listener.cancelListening()
    conversation = nil
    activity = .idle
    failure = nil
    spokenLine = nil
    lastTranscript = nil
    lastEvaluation = nil
    grant = nil
    listeningRoute = nil
    index = nil
    provider = nil
  }

  private func startListening() async {
    guard let conversation, isWaitingForSpeech(conversation.phase) else { return }
    failure = nil
    activity = .preparing
    dependencies.speaker.stopSpeaking()

    let allowServer = dependencies.allowsServerSpeech()
    let startedRun = run
    do {
      let route = try await dependencies.listener.prepare(
        language: language, allowServer: allowServer)
      guard startedRun == run else { return }
      listeningRoute = route
      try await dependencies.listener.startListening(
        language: language, allowServer: allowServer)
      guard startedRun == run else {
        dependencies.listener.cancelListening()
        return
      }
      activity = .listening(since: dependencies.now())
    } catch {
      guard startedRun == run else { return }
      activity = .idle
      failure = Self.failure(forListenerError: error)
    }
  }

  private func finishListening() async {
    activity = .transcribing
    let startedRun = run
    let transcript: String
    do {
      transcript = try await dependencies.listener.finishListening()
    } catch {
      guard startedRun == run else { return }
      activity = .idle
      failure = Self.failure(forListenerError: error)
      if failure == .nothingHeard { await say(phrases.nothingHeard) }
      return
    }
    guard startedRun == run else { return }
    lastTranscript = transcript
    await handle(transcript)
  }

  private func handle(_ transcript: String) async {
    guard var conversation else { return }
    switch conversation.phase {
    case .setup:
      guard conversation.answerSetup(transcript, index: index) == .advanced else {
        activity = .idle
        failure = .positionNotUnderstood
        await say(phrases.positionNotUnderstood)
        return
      }
      self.conversation = conversation
      if conversation.mode == .modelKnowledge, conversation.phase == .explaining,
        let subject = conversation.subject
      {
        dependencies.rememberSubject(subject)
      }
      await say(prompt(for: conversation))
    case .explaining:
      guard conversation.recordExplanation(transcript) else { return }
      self.conversation = conversation
      await evaluate()
    case .answering:
      guard conversation.recordAnswer(transcript) else { return }
      self.conversation = conversation
      await evaluate()
    case .evaluating, .finished:
      return
    }
  }

  private func evaluate() async {
    guard var conversation, let provider else { return }
    if !dependencies.hasProviderConsent(provider.host) {
      activity = .idle
      failure = .needsProviderConsent(host: provider.host)
      return
    }
    if let index {
      conversation.freezePassages(index: index)
      self.conversation = conversation
    }
    guard let request = conversation.evaluationRequest() else { return }

    activity = .evaluating
    failure = nil
    let startedRun = run
    let payload: StudyEvaluationPayload
    do {
      payload = try await provider.evaluate(request)
    } catch {
      guard startedRun == run else { return }
      await fail(.evaluationFailed(error as? StudyProviderError))
      return
    }
    guard startedRun == run else { return }
    guard case .success(let evaluation) = StudyEvaluationValidator.validate(payload, for: request)
    else {
      await fail(.invalidEvaluation)
      return
    }

    lastEvaluation = evaluation
    let step = StudyDecision.next(
      after: evaluation,
      request: request,
      followUpsAsked: conversation.followUpsAsked,
      decidedAt: dependencies.now()
    )
    conversation.apply(step)
    self.conversation = conversation
    activity = .idle

    switch step {
    case .askFollowUp(let question, let feedback):
      await say(phrases.followUp(feedback: feedback, question: question))
    case .approve(let approval, let feedback):
      await approve(approval, feedback: feedback)
    case .decline(_, let feedback):
      await say(phrases.declined(feedback: feedback))
    }
  }

  private func approve(_ approval: StudyApproval, feedback: String) async {
    do {
      let grant = try dependencies.unlock(approval)
      self.grant = grant
      let minutes = Int((grant.expiresAt.timeIntervalSince(grant.createdAt) / 60).rounded())
      await say(phrases.unlocked(feedback: feedback, minutes: minutes))
    } catch {
      failure = .unlockFailed(error.localizedDescription)
      await say(phrases.unlockFailed)
    }
  }

  private func fail(_ failure: Failure) async {
    activity = .idle
    self.failure = failure
    await say(phrases.evaluationFailed)
  }

  private func say(_ line: String) async {
    let startedRun = run
    spokenLine = line
    activity = .speaking
    await dependencies.speaker.speak(line, language: language)
    if startedRun == run, activity == .speaking { activity = .idle }
  }

  private func saveConsent(_ record: () throws -> Void) -> Bool {
    do {
      try record()
      failure = nil
      return true
    } catch {
      failure = .consentNotSaved
      return false
    }
  }

  private func prompt(for conversation: StudyConversation) -> String {
    switch conversation.phase {
    case .setup(.title): return phrases.askTitle
    case .setup(.author): return phrases.askAuthor
    case .setup(.position): return phrases.askPosition(for: conversation.mode)
    case .explaining: return phrases.askExplanation
    case .answering(let question): return question
    case .evaluating, .finished: return ""
    }
  }

  private func isWaitingForSpeech(_ phase: StudyConversation.Phase) -> Bool {
    switch phase {
    case .setup, .explaining, .answering: return true
    case .evaluating, .finished: return false
    }
  }

  private static func setupFailure(for error: Error) -> Failure {
    if case .missingCredential? = error as? StudyProviderError { return .missingCredential }
    return .providerNotConfigured
  }

  private static func failure(forListenerError error: Error) -> Failure {
    switch error as? StudyListenerError {
    case .microphoneDenied: return .microphoneDenied
    case .speechRecognitionDenied: return .speechRecognitionDenied
    case .languageUnsupported: return .languageUnavailable
    case .serverRecognitionNeedsConsent: return .needsServerSpeechConsent
    case .audioUnavailable: return .audioUnavailable
    case .nothingHeard, .recognitionFailed, nil: return .nothingHeard
    }
  }
}
