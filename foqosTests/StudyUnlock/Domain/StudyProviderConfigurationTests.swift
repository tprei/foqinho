import XCTest

@testable import foqos

final class StudyProviderConfigurationTests: XCTestCase {
  private func make(
    _ baseURL: String,
    model: String = "gpt-test"
  ) -> StudyProviderConfiguration? {
    StudyProviderConfiguration.make(baseURL: baseURL, model: model, responseFormat: .jsonSchema)
  }

  func testHttpsEndpointIsNormalized() throws {
    let configuration = try XCTUnwrap(make("  https://API.example.com/v1//  ", model: " gpt-test "))

    XCTAssertEqual(configuration.baseURL.absoluteString, "https://API.example.com/v1")
    XCTAssertEqual(configuration.host, "api.example.com")
    XCTAssertEqual(configuration.model, "gpt-test")
  }

  func testOnlyPlainHttpsEndpointsWithAModelAreAccepted() {
    XCTAssertNil(make("http://192.168.0.10:11434/v1"))
    XCTAssertNil(make("https:///v1"))
    XCTAssertNil(make("https://api.example.com/v1?key=secret"))
    XCTAssertNil(make("https://api.example.com/v1#models"))
    XCTAssertNil(make("api.example.com/v1"))
    XCTAssertNil(make("https://api.example.com/v1", model: "   "))
  }

  func testStoredConfigurationIsValidatedAgainWhenRead() throws {
    let configuration = try XCTUnwrap(make("https://openrouter.ai/api/v1"))
    let data = try JSONEncoder().encode(configuration)

    XCTAssertEqual(
      try JSONDecoder().decode(StudyProviderConfiguration.self, from: data), configuration)

    let tampered = Data(
      #"{"baseURL":"http://evil.example.com","model":"m","responseFormat":"jsonSchema"}"#.utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(StudyProviderConfiguration.self, from: tampered))
  }
}
