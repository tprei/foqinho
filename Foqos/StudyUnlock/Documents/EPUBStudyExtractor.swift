import Foundation
import ReadiumShared
import ReadiumStreamer

struct EPUBStudyExtractor {
  func extract(fileAt url: URL, fallbackTitle: String) async throws(StudyImportError)
    -> StudyExtraction
  {
    let publication = try await open(url)
    let hasEncryptedText = publication.readingOrder.contains { $0.properties.encryption != nil }
    guard !publication.isRestricted, !hasEncryptedText else { throw .protected }

    let blocks = try await textBlocks(of: publication)
    guard !blocks.isEmpty else { throw .noText }

    let title = publication.metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
    return StudyExtraction(
      title: title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle,
      author: publication.metadata.authors.first?.name,
      format: .epub,
      pageCount: nil,
      blocks: blocks,
      chapters: await chapterMarks(of: publication)
    )
  }

  private func open(_ url: URL) async throws(StudyImportError) -> Publication {
    guard let fileURL = FileURL(url: url) else { throw .unreadable }
    let httpClient = DefaultHTTPClient()
    let assetRetriever = AssetRetriever(httpClient: httpClient)
    let opener = PublicationOpener(
      parser: DefaultPublicationParser(
        httpClient: httpClient,
        assetRetriever: assetRetriever,
        pdfFactory: DefaultPDFDocumentFactory()
      )
    )

    guard case .success(let asset) = await assetRetriever.retrieve(url: fileURL) else {
      throw .unreadable
    }
    switch await opener.open(asset: asset, allowUserInteraction: false) {
    case .success(let publication):
      return publication
    case .failure:
      throw .unreadable
    }
  }

  private func textBlocks(of publication: Publication) async throws(StudyImportError)
    -> [StudyTextBlock]
  {
    guard let content = publication.content() else { throw .noText }
    let iterator = content.iterator()
    var hrefs: [String] = []
    var paragraphs: [String: [String]] = [:]
    do {
      while let element = try await iterator.next() {
        guard let text = (element as? TextContentElement)?.text, !text.isEmpty else { continue }
        let href = element.locator.href.removingFragment().string
        if paragraphs[href] == nil { hrefs.append(href) }
        paragraphs[href, default: []].append(text)
      }
    } catch {
      throw .unreadable
    }
    return hrefs.map { href in
      StudyTextBlock(
        origin: .epubResource(href: href),
        text: paragraphs[href, default: []].joined(separator: "\n\n")
      )
    }
  }

  private func chapterMarks(of publication: Publication) async -> [StudyChapterMark] {
    guard case .success(let tableOfContents) = await publication.tableOfContents() else {
      return []
    }
    let links = tableOfContents.flatMap { [$0] + $0.children }
    return links.compactMap { link in
      guard let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines),
        !title.isEmpty
      else {
        return nil
      }
      let href = link.url().removingFragment().string
      return StudyChapterMark(title: title, start: .epubResource(href: href))
    }
  }
}
