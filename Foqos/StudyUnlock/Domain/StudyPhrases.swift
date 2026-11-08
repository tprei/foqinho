import Foundation

struct StudyPhrases {
  let language: StudyLanguage

  init(language: StudyLanguage) {
    self.language = language
  }

  func modeDisclosure(for source: StudySource) -> String {
    switch (source, language) {
    case (.document(let document), .portugueseBrazil):
      return "Modo documento: vou avaliar com trechos de \(document.title)."
    case (.document(let document), .englishUS):
      return "Document mode: I'll check your explanation against passages from \(document.title)."
    case (.modelKnowledge, .portugueseBrazil):
      return
        "Modo conhecimento do modelo: a avaliação usa o que o modelo sabe sobre o livro e pode errar."
    case (.modelKnowledge, .englishUS):
      return
        "Model knowledge mode: the evaluation uses what the model knows about the book, and it can be wrong."
    }
  }

  var askTitle: String {
    switch language {
    case .portugueseBrazil: return "Qual é o título do livro?"
    case .englishUS: return "What's the title of the book?"
    }
  }

  var askAuthor: String {
    switch language {
    case .portugueseBrazil: return "Quem é o autor? Se não souber, diga não sei."
    case .englishUS: return "Who's the author? If you're not sure, say I don't know."
    }
  }

  func askPosition(for mode: StudyMode) -> String {
    switch (mode, language) {
    case (.document, .portugueseBrazil):
      return "Em que parte você está? Diga, por exemplo, páginas 40 a 52, ou capítulo 3."
    case (.document, .englishUS):
      return "Where are you in the book? Say, for example, pages 40 to 52, or chapter 3."
    case (.modelKnowledge, .portugueseBrazil):
      return "Em que parte do livro você está? Pode dizer o capítulo, as páginas ou o tema."
    case (.modelKnowledge, .englishUS):
      return "Where are you in the book? Say the chapter, the pages or the topic."
    }
  }

  var askExplanation: String {
    switch language {
    case .portugueseBrazil: return "Agora explique, com suas palavras, o que você leu."
    case .englishUS: return "Now explain, in your own words, what you read."
    }
  }

  var positionNotUnderstood: String {
    switch language {
    case .portugueseBrazil:
      return "Não encontrei essa parte no arquivo. Diga as páginas ou o número do capítulo."
    case .englishUS:
      return "I couldn't find that part in the file. Say the pages or the chapter number."
    }
  }

  var nothingHeard: String {
    switch language {
    case .portugueseBrazil: return "Não consegui ouvir. Toque para tentar de novo."
    case .englishUS: return "I didn't catch that. Tap to try again."
    }
  }

  func followUp(feedback: String, question: String) -> String {
    "\(feedback) \(question)"
  }

  func unlocked(feedback: String, minutes: Int) -> String {
    switch language {
    case .portugueseBrazil: return "\(feedback) Liberado por \(minutes) minutos."
    case .englishUS: return "\(feedback) Unlocked for \(minutes) minutes."
    }
  }

  func declined(feedback: String) -> String {
    switch language {
    case .portugueseBrazil: return "\(feedback) Desta vez não liberei. Você pode tentar de novo."
    case .englishUS: return "\(feedback) Not unlocked this time. You can try again."
    }
  }

  var evaluationFailed: String {
    switch language {
    case .portugueseBrazil:
      return "Não consegui avaliar agora. Nada foi liberado. Toque para tentar de novo."
    case .englishUS:
      return "I couldn't evaluate that right now. Nothing was unlocked. Tap to try again."
    }
  }

  var unlockFailed: String {
    switch language {
    case .portugueseBrazil:
      return "Você foi aprovado, mas não consegui pausar o bloqueio. Nada mudou."
    case .englishUS:
      return "You passed, but I couldn't pause blocking. Nothing changed."
    }
  }
}
