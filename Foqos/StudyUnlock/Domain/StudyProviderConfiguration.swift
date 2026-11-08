import Foundation

struct StudyProviderConfiguration: Codable, Equatable {
  enum ResponseFormat: String, Codable, CaseIterable {
    case jsonSchema
    case jsonObject
  }

  struct InvalidConfiguration: Error {}

  let baseURL: URL
  let host: String
  let model: String
  let responseFormat: ResponseFormat

  private enum CodingKeys: String, CodingKey {
    case baseURL
    case model
    case responseFormat
  }

  private init(baseURL: URL, host: String, model: String, responseFormat: ResponseFormat) {
    self.baseURL = baseURL
    self.host = host
    self.model = model
    self.responseFormat = responseFormat
  }

  static func make(
    baseURL: String,
    model: String,
    responseFormat: ResponseFormat
  ) -> StudyProviderConfiguration? {
    var address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while address.hasSuffix("/") { address.removeLast() }
    let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let url = URLComponents(string: address),
      url.scheme?.lowercased() == "https",
      let host = url.host, !host.isEmpty,
      url.query == nil, url.fragment == nil,
      let parsed = url.url,
      !trimmedModel.isEmpty
    else {
      return nil
    }
    return StudyProviderConfiguration(
      baseURL: parsed, host: host.lowercased(), model: trimmedModel, responseFormat: responseFormat)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard
      let configuration = Self.make(
        baseURL: try container.decode(String.self, forKey: .baseURL),
        model: try container.decode(String.self, forKey: .model),
        responseFormat: try container.decode(ResponseFormat.self, forKey: .responseFormat)
      )
    else {
      throw InvalidConfiguration()
    }
    self = configuration
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(baseURL.absoluteString, forKey: .baseURL)
    try container.encode(model, forKey: .model)
    try container.encode(responseFormat, forKey: .responseFormat)
  }
}
