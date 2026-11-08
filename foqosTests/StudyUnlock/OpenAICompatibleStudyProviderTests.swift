import XCTest

@testable import foqos

final class StudyProviderStubProtocol: URLProtocol {
  static var respond: ((URLRequest) throws -> (Int, Data))?
  static var capturedRequest: URLRequest?
  static var capturedBody: Data?
  static var redirectTarget: URL?
  static var requestedURLs: [URL] = []

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.capturedRequest = request
    Self.capturedBody = Self.body(of: request)
    do {
      guard let respond = Self.respond, let url = request.url else {
        throw URLError(.badServerResponse)
      }
      Self.requestedURLs.append(url)
      let (status, data) = try respond(request)
      let redirect = Self.redirectTarget.flatMap { $0 == url ? nil : $0 }
      let response = HTTPURLResponse(
        url: url, statusCode: status, httpVersion: nil,
        headerFields: redirect.map { ["Location": $0.absoluteString] })
      if let redirect, let response {
        client?.urlProtocol(
          self, wasRedirectedTo: URLRequest(url: redirect), redirectResponse: response)
      }
      client?.urlProtocol(
        self, didReceive: response ?? URLResponse(), cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}

  private static func body(of request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

final class OpenAICompatibleStudyProviderTests: XCTestCase {
  private let apiKey = "sk-test-secret"

  override func tearDown() {
    StudyProviderStubProtocol.respond = nil
    StudyProviderStubProtocol.capturedRequest = nil
    StudyProviderStubProtocol.capturedBody = nil
    StudyProviderStubProtocol.redirectTarget = nil
    StudyProviderStubProtocol.requestedURLs = []
    super.tearDown()
  }

  private func provider(
    format: StudyProviderConfiguration.ResponseFormat = .jsonSchema
  ) throws -> OpenAICompatibleStudyProvider {
    let configuration = try XCTUnwrap(
      StudyProviderConfiguration.make(
        baseURL: "https://api.example.com/v1", model: "gpt-test", responseFormat: format))
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [StudyProviderStubProtocol.self]
    return OpenAICompatibleStudyProvider(
      configuration: configuration,
      apiKey: apiKey,
      session: URLSession(configuration: sessionConfiguration)
    )
  }

  private func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
  }

  private func respond(status: Int, fixture name: String) throws {
    let data = try fixture(name)
    StudyProviderStubProtocol.respond = { _ in (status, data) }
  }

  private func evaluationError(
    _ provider: OpenAICompatibleStudyProvider
  ) async -> StudyProviderError? {
    do {
      _ = try await provider.evaluate(StudyDomainFixtures.request())
      return nil
    } catch {
      return error as? StudyProviderError
    }
  }

  private func sentBody() throws -> [String: Any] {
    let body = try XCTUnwrap(StudyProviderStubProtocol.capturedBody)
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
  }

  func testPassResponseBecomesAPayload() async throws {
    try respond(status: 200, fixture: "study-chat-completion-pass")

    let payload = try await provider().evaluate(StudyDomainFixtures.request())

    XCTAssertEqual(payload.decision, "pass")
    XCTAssertEqual(payload.evidence.map(\.chunkId), ["p41.1"])
    XCTAssertEqual(payload.spokenFeedback, "Você explicou bem de onde vem o ATP.")
  }

  func testARedirectIsNeverFollowed() async throws {
    let pass = try fixture("study-chat-completion-pass")
    let elsewhere = try XCTUnwrap(URL(string: "https://elsewhere.example.net/v1/chat/completions"))
    StudyProviderStubProtocol.redirectTarget = elsewhere
    StudyProviderStubProtocol.respond = { request in
      request.url == elsewhere ? (200, pass) : (307, Data())
    }

    let error = await evaluationError(try provider())

    XCTAssertEqual(error, .httpStatus(307))
    XCTAssertEqual(StudyProviderStubProtocol.requestedURLs.count, 1)
    XCTAssertFalse(StudyProviderStubProtocol.requestedURLs.contains(elsewhere))
  }

  func testRefusalProseAndErrorsNeverBecomeAPayload() async throws {
    try respond(status: 200, fixture: "study-chat-completion-refusal")
    let refusal = await evaluationError(try provider())
    XCTAssertEqual(refusal, .refused)

    try respond(status: 200, fixture: "study-chat-completion-prose")
    let prose = await evaluationError(try provider())
    XCTAssertEqual(prose, .malformedResponse)

    try respond(status: 401, fixture: "study-error-401")
    let unauthorized = await evaluationError(try provider())
    XCTAssertEqual(unauthorized, .httpStatus(401))

    StudyProviderStubProtocol.respond = { _ in (429, Data("{}".utf8)) }
    let rateLimited = await evaluationError(try provider())
    XCTAssertEqual(rateLimited, .httpStatus(429))
  }

  func testNetworkFailuresAreTimeoutOrOffline() async throws {
    StudyProviderStubProtocol.respond = { _ in throw URLError(.timedOut) }
    let timeout = await evaluationError(try provider())
    XCTAssertEqual(timeout, .timedOut)

    StudyProviderStubProtocol.respond = { _ in throw URLError(.notConnectedToInternet) }
    let offline = await evaluationError(try provider())
    XCTAssertEqual(offline, .offline)
  }

  func testRequestCarriesTheStrictSchemaAndOnlyTheRequestPassages() async throws {
    try respond(status: 200, fixture: "study-chat-completion-pass")
    let request = StudyDomainFixtures.request(
      passages: Array(StudyDomainFixtures.passages.prefix(2)))

    _ = try await provider().evaluate(request)

    let sent = try XCTUnwrap(StudyProviderStubProtocol.capturedRequest)
    XCTAssertEqual(sent.url?.absoluteString, "https://api.example.com/v1/chat/completions")
    XCTAssertEqual(sent.httpMethod, "POST")
    XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer \(apiKey)")

    let body = try sentBody()
    XCTAssertEqual(body["model"] as? String, "gpt-test")
    XCTAssertNil(body["temperature"])
    XCTAssertNil(body["max_tokens"])
    XCTAssertNil(body["max_completion_tokens"])

    let format = try XCTUnwrap(body["response_format"] as? [String: Any])
    XCTAssertEqual(format["type"] as? String, "json_schema")
    let schema = try XCTUnwrap(format["json_schema"] as? [String: Any])
    XCTAssertEqual(schema["name"] as? String, StudyEvaluationSchema.name)
    XCTAssertEqual(schema["strict"] as? Bool, true)
    XCTAssertNotNil(schema["schema"] as? [String: Any])

    let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
    XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
    let userContent = try XCTUnwrap(messages.last?["content"])
    XCTAssertTrue(userContent.contains("id=\"p40.1\""))
    XCTAssertTrue(userContent.contains("id=\"p41.1\""))
    XCTAssertFalse(userContent.contains("id=\"p41.2\""))
  }

  func testKeyIsSentOnlyInTheAuthorizationHeader() async throws {
    try respond(status: 200, fixture: "study-chat-completion-pass")

    _ = try await provider().evaluate(StudyDomainFixtures.request())

    let sent = try XCTUnwrap(StudyProviderStubProtocol.capturedRequest)
    let body = try XCTUnwrap(StudyProviderStubProtocol.capturedBody)
    XCTAssertFalse(sent.url?.absoluteString.contains(apiKey) ?? true)
    XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(apiKey))
  }

  func testJsonObjectFormatWhenConfigured() async throws {
    try respond(status: 200, fixture: "study-chat-completion-pass")

    _ = try await provider(format: .jsonObject).evaluate(StudyDomainFixtures.request())

    let format = try XCTUnwrap(try sentBody()["response_format"] as? [String: Any])
    XCTAssertEqual(format["type"] as? String, "json_object")
    XCTAssertNil(format["json_schema"])
  }
}
