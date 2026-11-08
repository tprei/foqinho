import Foundation

extension URLSession {
  static let studyProvider: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 45
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    return URLSession(configuration: configuration)
  }()
}

// A redirect would re-send the conversation to a host the user never allowed, so the 3xx
// response comes back as an HTTP error instead.
private final class StudyProviderRedirectRefusal: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

struct OpenAICompatibleStudyProvider: StudyModelProvider {
  private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable {
        let content: String?
        let refusal: String?
      }

      let message: Message
    }

    let choices: [Choice]
  }

  private static let offlineCodes: Set<URLError.Code> = [
    .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
    .dataNotAllowed,
  ]

  let configuration: StudyProviderConfiguration
  private let apiKey: String
  private let session: URLSession

  init(
    configuration: StudyProviderConfiguration,
    apiKey: String,
    session: URLSession = .studyProvider
  ) {
    self.configuration = configuration
    self.apiKey = apiKey
    self.session = session
  }

  var host: String { configuration.host }

  func evaluate(_ request: StudyEvaluationRequest) async throws -> StudyEvaluationPayload {
    let (data, response) = try await send(try urlRequest(for: request))
    guard let httpResponse = response as? HTTPURLResponse else {
      throw StudyProviderError.malformedResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw StudyProviderError.httpStatus(httpResponse.statusCode)
    }
    return try payload(from: data)
  }

  private func urlRequest(for request: StudyEvaluationRequest) throws -> URLRequest {
    var urlRequest = URLRequest(
      url: configuration.baseURL.appendingPathComponent("chat/completions"))
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(for: request))
    return urlRequest
  }

  private func body(for request: StudyEvaluationRequest) throws -> [String: Any] {
    let messages = StudyPromptBuilder.messages(for: request).map { message in
      ["role": message.role.rawValue, "content": message.content]
    }
    return [
      "model": configuration.model,
      "messages": messages,
      "response_format": try responseFormat(),
    ]
  }

  private func responseFormat() throws -> [String: Any] {
    switch configuration.responseFormat {
    case .jsonObject:
      return ["type": "json_object"]
    case .jsonSchema:
      let schema = try JSONSerialization.jsonObject(with: Data(StudyEvaluationSchema.json.utf8))
      return [
        "type": "json_schema",
        "json_schema": ["name": StudyEvaluationSchema.name, "strict": true, "schema": schema],
      ]
    }
  }

  private func send(_ urlRequest: URLRequest) async throws -> (Data, URLResponse) {
    do {
      return try await session.data(for: urlRequest, delegate: StudyProviderRedirectRefusal())
    } catch let error as URLError where error.code == .timedOut {
      throw StudyProviderError.timedOut
    } catch let error as URLError where Self.offlineCodes.contains(error.code) {
      throw StudyProviderError.offline
    } catch {
      throw StudyProviderError.malformedResponse
    }
  }

  private func payload(from data: Data) throws -> StudyEvaluationPayload {
    let message: ChatCompletion.Choice.Message
    do {
      let completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
      guard let first = completion.choices.first?.message else {
        throw StudyProviderError.malformedResponse
      }
      message = first
    } catch {
      throw StudyProviderError.malformedResponse
    }

    if let refusal = message.refusal, !refusal.isEmpty { throw StudyProviderError.refused }
    guard let content = message.content else { throw StudyProviderError.malformedResponse }
    do {
      return try StudyEvaluationPayload.decode(from: content)
    } catch {
      throw StudyProviderError.malformedResponse
    }
  }
}
