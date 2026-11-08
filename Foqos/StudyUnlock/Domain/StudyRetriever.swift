import Foundation

struct StudyWindow: Equatable {
  let label: String
  let passages: [StudyPassage]
}

enum StudyRetriever {
  static let passageBudget = 12_000
  static let minimumWindowCharacters = 1_500
  private static let minimumKeywordLength = 4

  static func window(for position: StudyPosition, in index: StudyDocumentIndex) -> StudyWindow? {
    switch position {
    case .pages(let first, let last):
      let range = index.passages.indices.filter { offset in
        guard case .pdfPage(let page) = index.passages[offset].locator else { return false }
        return (first...last).contains(page)
      }
      return window(passageRange: range, in: index)
    case .chapter(let number):
      return chapter(numbered: number, in: index.chapters).flatMap { window(for: $0, in: index) }
    case .chapterTitle(let words):
      return chapter(titled: words, in: index).flatMap { window(for: $0, in: index) }
    }
  }

  static func select(
    from window: StudyWindow,
    explanation: String,
    in index: StudyDocumentIndex
  ) -> [StudyPassage] {
    let widened = widen(window.passages, in: index)
    guard characterCount(of: widened) > passageBudget else { return widened }

    let keywords = significantWords(in: explanation)
    let ranked = widened.enumerated().sorted { lhs, rhs in
      let lhsScore = significantWords(in: lhs.element.text).intersection(keywords).count
      let rhsScore = significantWords(in: rhs.element.text).intersection(keywords).count
      guard lhsScore == rhsScore else { return lhsScore > rhsScore }
      return lhs.offset > rhs.offset
    }

    var kept: Set<Int> = []
    var used = 0
    for (offset, passage) in ranked where used + passage.text.count <= passageBudget {
      kept.insert(offset)
      used += passage.text.count
    }
    return widened.enumerated().filter { kept.contains($0.offset) }.map(\.element)
  }

  private static func window(for chapter: StudyChapter, in index: StudyDocumentIndex)
    -> StudyWindow?
  {
    let nextStart =
      index.chapters
      .map(\.firstPassageIndex)
      .filter { $0 > chapter.firstPassageIndex }
      .min() ?? index.passages.count
    return window(passageRange: Array(chapter.firstPassageIndex..<nextStart), in: index)
  }

  private static func window(passageRange: [Int], in index: StudyDocumentIndex) -> StudyWindow? {
    guard let firstOffset = passageRange.first, let lastOffset = passageRange.last else {
      return nil
    }
    let passages = passageRange.map { index.passages[$0] }
    return StudyWindow(
      label: label(from: index.passages[firstOffset], to: index.passages[lastOffset]),
      passages: passages
    )
  }

  private static func label(from first: StudyPassage, to last: StudyPassage) -> String {
    guard case .pdfPage(let firstPage) = first.locator, case .pdfPage(let lastPage) = last.locator
    else {
      return first.locator.label
    }
    guard firstPage != lastPage else { return "p. \(firstPage)" }
    return "pp. \(firstPage)–\(lastPage)"
  }

  private static func chapter(numbered number: Int, in chapters: [StudyChapter]) -> StudyChapter? {
    let chapterWords: Set<String> = ["capitulo", "cap", "chapter", "ch"]
    let numberSpellings = Set(
      [String(number), StudyPositionParser.romanSpelling(of: number)].compactMap { $0 })
    let titled = chapters.first { chapter in
      let words = titleWords(chapter.title)
      if let firstWord = words.first, numberSpellings.contains(firstWord) { return true }
      return zip(words, words.dropFirst()).contains { previous, word in
        chapterWords.contains(previous) && numberSpellings.contains(word)
      }
    }
    return titled ?? chapters.first { $0.ordinal == number }
  }

  private static func chapter(titled words: String, in index: StudyDocumentIndex) -> StudyChapter? {
    let phrase = StudyText.folded(words)
    if let containing = index.chapters.first(where: { StudyText.folded($0.title).contains(phrase) })
    {
      return containing
    }

    let wanted = significantWords(in: words)
    let scored = index.chapters.map {
      ($0, significantWords(in: $0.title).intersection(wanted).count)
    }
    guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
    return scored.first { $0.1 == best.1 }?.0
  }

  private static func widen(_ passages: [StudyPassage], in index: StudyDocumentIndex)
    -> [StudyPassage]
  {
    let ids = Set(passages.map(\.id))
    let offsets = index.passages.indices.filter { ids.contains(index.passages[$0].id) }
    guard var lower = offsets.first, var upper = offsets.last else { return passages }

    var total = characterCount(of: passages)
    while total < minimumWindowCharacters {
      let canGrowForward = upper + 1 < index.passages.count
      let canGrowBackward = lower > 0
      guard canGrowForward || canGrowBackward else { break }
      if canGrowForward {
        upper += 1
        total += index.passages[upper].text.count
      }
      if total < minimumWindowCharacters, canGrowBackward {
        lower -= 1
        total += index.passages[lower].text.count
      }
    }
    return Array(index.passages[lower...upper])
  }

  private static func characterCount(of passages: [StudyPassage]) -> Int {
    passages.reduce(0) { $0 + $1.text.count }
  }

  private static func significantWords(in text: String) -> Set<String> {
    Set(titleWords(text).filter { $0.count >= minimumKeywordLength && $0.allSatisfy(\.isLetter) })
  }

  private static func titleWords(_ text: String) -> [String] {
    StudyText.folded(text)
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .map(String.init)
  }
}
