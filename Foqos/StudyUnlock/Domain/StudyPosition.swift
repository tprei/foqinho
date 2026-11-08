import Foundation

enum StudyPosition: Equatable {
  case pages(first: Int, last: Int)
  case chapter(Int)
  case chapterTitle(String)
}
