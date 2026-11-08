import Foundation

enum StudyPositionParser {
  static func parse(_ transcript: String, language: StudyLanguage) -> StudyPosition? {
    let tokens = tokenize(transcript)
    let vocabulary = StudyPositionVocabulary(language: language)

    if let pages = pages(in: tokens, vocabulary: vocabulary) { return pages }
    if let chapter = chapterNumber(in: tokens, vocabulary: vocabulary) { return chapter }
    return chapterTitle(in: tokens, vocabulary: vocabulary)
  }

  private static func tokenize(_ transcript: String) -> [String] {
    let spacedHyphens = StudyText.folded(transcript).replacingOccurrences(of: "-", with: " - ")
    let kept = spacedHyphens.unicodeScalars.map { scalar -> Character in
      CharacterSet.alphanumerics.contains(scalar) || scalar == "-" ? Character(scalar) : " "
    }
    return String(kept).split(separator: " ").map(String.init)
  }

  private static func pages(
    in tokens: [String],
    vocabulary: StudyPositionVocabulary
  ) -> StudyPosition? {
    for index in tokens.indices where vocabulary.pageWords.contains(tokens[index]) {
      guard let first = number(at: index + 1, in: tokens, vocabulary: vocabulary, allowRoman: false)
      else { continue }

      let last = rangeEnd(after: first.next, in: tokens, vocabulary: vocabulary)
      let lastPage = last ?? first.value
      return .pages(first: min(first.value, lastPage), last: max(first.value, lastPage))
    }
    return nil
  }

  private static func rangeEnd(
    after start: Int,
    in tokens: [String],
    vocabulary: StudyPositionVocabulary
  ) -> Int? {
    var index = start
    var skipped = 0
    while index < tokens.count, skipped < 3, vocabulary.rangeFillers.contains(tokens[index]) {
      index += 1
      skipped += 1
    }
    guard skipped > 0 else { return nil }
    return number(at: index, in: tokens, vocabulary: vocabulary, allowRoman: false)?.value
  }

  private static func chapterNumber(
    in tokens: [String],
    vocabulary: StudyPositionVocabulary
  ) -> StudyPosition? {
    for index in tokens.indices where vocabulary.chapterWords.contains(tokens[index]) {
      if let chapter = number(at: index + 1, in: tokens, vocabulary: vocabulary, allowRoman: true) {
        return .chapter(chapter.value)
      }
    }
    return nil
  }

  private static func chapterTitle(
    in tokens: [String],
    vocabulary: StudyPositionVocabulary
  ) -> StudyPosition? {
    for index in tokens.indices where vocabulary.chapterWords.contains(tokens[index]) {
      let next = index + 1
      guard next < tokens.count, vocabulary.titleIntroducers.contains(tokens[next]) else {
        continue
      }
      let words = tokens[(next + 1)...].filter { !vocabulary.titleFillers.contains($0) }
      guard !words.isEmpty else { return nil }
      return .chapterTitle(words.joined(separator: " "))
    }
    return nil
  }

  private static func number(
    at index: Int,
    in tokens: [String],
    vocabulary: StudyPositionVocabulary,
    allowRoman: Bool
  ) -> (value: Int, next: Int)? {
    guard index < tokens.count else { return nil }
    let token = tokens[index]

    if let digits = Int(token), digits > 0 { return (digits, index + 1) }
    if allowRoman, let roman = romanNumeral(token) { return (roman, index + 1) }
    return spelledNumber(at: index, in: tokens, vocabulary: vocabulary)
  }

  private static func spelledNumber(
    at index: Int,
    in tokens: [String],
    vocabulary: StudyPositionVocabulary
  ) -> (value: Int, next: Int)? {
    let token = tokens[index]
    if let unit = vocabulary.units[token] { return (unit, index + 1) }
    guard let tens = vocabulary.tens[token] else { return nil }

    var unitIndex = index + 1
    if unitIndex < tokens.count, vocabulary.compoundJoiners.contains(tokens[unitIndex]) {
      unitIndex += 1
    }
    if unitIndex < tokens.count, let unit = vocabulary.units[tokens[unitIndex]], unit < 10 {
      return (tens + unit, unitIndex + 1)
    }
    return (tens, index + 1)
  }

  private static func romanNumeral(_ token: String) -> Int? {
    let values: [Character: Int] = ["i": 1, "v": 5, "x": 10]
    guard !token.isEmpty, token.count <= 6, token.allSatisfy({ values[$0] != nil }) else {
      return nil
    }

    let digits = token.compactMap { values[$0] }
    var total = 0
    for (offset, value) in digits.enumerated() {
      let following = offset + 1 < digits.count ? digits[offset + 1] : 0
      total += value < following ? -value : value
    }
    guard (1...30).contains(total), romanSpelling(of: total) == token else { return nil }
    return total
  }

  static func romanSpelling(of value: Int) -> String? {
    guard (1...30).contains(value) else { return nil }
    let tens = String(repeating: "x", count: value / 10)
    let units = ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"][value % 10]
    return tens + units
  }
}

private struct StudyPositionVocabulary {
  let pageWords: Set<String>
  let chapterWords: Set<String>
  let rangeFillers: Set<String>
  let titleIntroducers: Set<String>
  let titleFillers: Set<String>
  let compoundJoiners: Set<String>
  let units: [String: Int]
  let tens: [String: Int]

  init(language: StudyLanguage) {
    switch language {
    case .portugueseBrazil:
      pageWords = ["pagina", "paginas", "pag", "pags"]
      chapterWords = ["capitulo", "capitulos", "cap"]
      rangeFillers = ["a", "ate", "e", "-", "pagina", "paginas", "pag", "na", "para"]
      titleIntroducers = ["sobre", "chamado", "chamada", "intitulado", "intitulada"]
      titleFillers = ["o", "a", "os", "as", "de", "do", "da", "dos", "das"]
      compoundJoiners = ["e"]
      units = Self.portugueseUnits
      tens = [
        "vinte": 20, "trinta": 30, "quarenta": 40, "cinquenta": 50, "sessenta": 60,
        "setenta": 70, "oitenta": 80, "noventa": 90,
      ]
    case .englishUS:
      pageWords = ["page", "pages", "p", "pp"]
      chapterWords = ["chapter", "chapters", "ch"]
      rangeFillers = ["to", "through", "thru", "and", "-", "page", "pages"]
      titleIntroducers = ["about", "called", "named", "titled"]
      titleFillers = ["the", "a", "an", "of"]
      compoundJoiners = ["-"]
      units = Self.englishUnits
      tens = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
        "eighty": 80, "ninety": 90,
      ]
    }
  }

  private static let portugueseUnits: [String: Int] = [
    "um": 1, "uma": 1, "dois": 2, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6,
    "sete": 7, "oito": 8, "nove": 9, "dez": 10, "onze": 11, "doze": 12, "treze": 13,
    "catorze": 14, "quatorze": 14, "quinze": 15, "dezesseis": 16, "dezasseis": 16,
    "dezessete": 17, "dezassete": 17, "dezoito": 18, "dezenove": 19, "dezanove": 19,
  ]

  private static let englishUnits: [String: Int] = [
    "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
    "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
    "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
  ]
}
