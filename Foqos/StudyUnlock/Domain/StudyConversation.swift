import Foundation

struct StudyConversation: Equatable {
  enum SetupQuestion: Equatable {
    case title
    case author
    case position
  }

  enum Phase: Equatable {
    case setup(SetupQuestion)
    case explaining
    case answering(question: String)
    case evaluating
    case finished(StudyStep)
  }

  enum SetupOutcome: Equatable {
    case advanced
    case notUnderstood
  }

  private struct DeclaredBook: Equatable {
    var title: String
    var author: String?
  }

  private static let unknownAuthorAnswers: Set<String> = [
    "nao sei", "eu nao sei", "i don't know", "don't know", "i dont know", "dont know",
  ]

  let source: StudySource
  let language: StudyLanguage
  private(set) var phase: Phase
  private(set) var subject: StudySubject?
  private(set) var window: StudyWindow?
  private(set) var passages: [StudyPassage] = []
  private(set) var turns: [StudyTurn] = []
  private(set) var followUpsAsked = 0
  private var declaredBook: DeclaredBook?

  var mode: StudyMode {
    switch source {
    case .document: return .document
    case .modelKnowledge: return .modelKnowledge
    }
  }

  init(source: StudySource, language: StudyLanguage) {
    self.source = source
    self.language = language
    switch source {
    case .document:
      phase = .setup(.position)
    case .modelKnowledge(let remembered?):
      declaredBook = DeclaredBook(title: remembered.title, author: remembered.author)
      phase = .setup(.position)
    case .modelKnowledge(nil):
      phase = .setup(.title)
    }
  }

  mutating func answerSetup(_ transcript: String, index: StudyDocumentIndex?) -> SetupOutcome {
    let answer = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard case .setup(let question) = phase, !answer.isEmpty else { return .notUnderstood }

    switch (source, question) {
    case (.document(let document), .position):
      guard let index,
        let position = StudyPositionParser.parse(answer, language: language),
        let window = StudyRetriever.window(for: position, in: index)
      else {
        return .notUnderstood
      }
      self.window = window
      subject = StudySubject(title: document.title, author: document.author, position: window.label)
      phase = .explaining
    case (.modelKnowledge, .title):
      declaredBook = DeclaredBook(title: answer, author: nil)
      phase = .setup(.author)
    case (.modelKnowledge, .author):
      let folded = StudyText.folded(answer).trimmingCharacters(in: .punctuationCharacters)
      declaredBook?.author = Self.unknownAuthorAnswers.contains(folded) ? nil : answer
      phase = .setup(.position)
    case (.modelKnowledge, .position):
      guard let declaredBook else { return .notUnderstood }
      subject = StudySubject(
        title: declaredBook.title, author: declaredBook.author, position: answer)
      phase = .explaining
    case (.document, .title), (.document, .author):
      return .notUnderstood
    }
    return .advanced
  }

  mutating func recordExplanation(_ transcript: String) -> Bool {
    let explanation = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard phase == .explaining, !explanation.isEmpty else { return false }
    turns.append(.explanation(explanation))
    phase = .evaluating
    return true
  }

  mutating func recordAnswer(_ transcript: String) -> Bool {
    let answer = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard case .answering(let question) = phase, !answer.isEmpty else { return false }
    turns.append(.followUp(question: question, answer: answer))
    phase = .evaluating
    return true
  }

  mutating func freezePassages(index: StudyDocumentIndex) {
    guard passages.isEmpty, let window, case .explanation(let explanation)? = turns.first else {
      return
    }
    passages = StudyRetriever.select(from: window, explanation: explanation, in: index)
  }

  func evaluationRequest() -> StudyEvaluationRequest? {
    guard phase == .evaluating, let subject else { return nil }
    return StudyEvaluationRequest(
      mode: mode,
      language: language,
      subject: subject,
      passages: passages,
      turns: turns,
      followUpsRemaining: StudyDecision.maximumFollowUps - followUpsAsked
    )
  }

  mutating func apply(_ step: StudyStep) {
    guard phase == .evaluating else { return }
    switch step {
    case .askFollowUp(let question, _):
      followUpsAsked += 1
      phase = .answering(question: question)
    case .approve, .decline:
      phase = .finished(step)
    }
  }
}
