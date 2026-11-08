import XCTest

@testable import foqos

final class StudyProviderSettingsStoreTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUpWithError() throws {
    suiteName = "StudyProviderSettingsStoreTests-\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  func testSettingsRoundTripAndStartFromDefaults() throws {
    let store = StudyProviderSettingsStore(defaults: defaults)
    XCTAssertEqual(store.load(), StudyProviderSettingsStore.Settings())
    XCTAssertEqual(store.load().language, .portugueseBrazil)

    var settings = store.load()
    settings.configuration = StudyProviderConfiguration.make(
      baseURL: "https://openrouter.ai/api/v1", model: "some/model", responseFormat: .jsonObject)
    settings.language = .englishUS
    settings.allowsServerSpeech = true
    try store.save(settings)

    XCTAssertEqual(StudyProviderSettingsStore(defaults: defaults).load(), settings)
  }

  func testConsentIsPerHostAndRevocable() throws {
    let store = StudyProviderSettingsStore(defaults: defaults)

    try store.recordConsent(host: "api.openai.com")
    try store.recordConsent(host: "api.openai.com")

    XCTAssertTrue(store.hasConsent(host: "api.openai.com"))
    XCTAssertFalse(store.hasConsent(host: "openrouter.ai"))
    XCTAssertEqual(store.load().consentedHosts, ["api.openai.com"])

    try store.revokeConsent(host: "api.openai.com")

    XCTAssertFalse(store.hasConsent(host: "api.openai.com"))
  }

  func testFactoryNeedsAConfigurationAndAKeyForItsHost() throws {
    let store = StudyProviderSettingsStore(defaults: defaults)
    XCTAssertThrowsError(try StudyProviderFactory.make(settings: store, apiKey: { _ in "k" })) {
      XCTAssertEqual($0 as? StudyProviderError, .notConfigured)
    }

    var settings = store.load()
    settings.configuration = StudyProviderConfiguration.make(
      baseURL: "https://api.example.com/v1", model: "gpt-test", responseFormat: .jsonSchema)
    try store.save(settings)

    XCTAssertThrowsError(try StudyProviderFactory.make(settings: store, apiKey: { _ in nil })) {
      XCTAssertEqual($0 as? StudyProviderError, .missingCredential)
    }
    var askedHost: String?
    XCTAssertNoThrow(
      try StudyProviderFactory.make(
        settings: store,
        apiKey: { host in
          askedHost = host
          return "sk-test"
        }))
    XCTAssertEqual(askedHost, "api.example.com")
  }
}

final class StudyCredentialStoreTests: XCTestCase {
  private var hosts: [String] = []

  override func tearDownWithError() throws {
    for host in hosts {
      try StudyCredentialStore.delete(host: host)
    }
  }

  private func uniqueHost() -> String {
    let host = "test-\(UUID().uuidString.lowercased()).example.com"
    hosts.append(host)
    return host
  }

  func testSavingTwiceUpdatesTheKey() throws {
    let host = uniqueHost()

    try StudyCredentialStore.save(apiKey: "first", host: host)
    try StudyCredentialStore.save(apiKey: "second", host: host)

    XCTAssertEqual(try StudyCredentialStore.apiKey(host: host), "second")
  }

  func testKeysAreSeparatePerHostAndDeletable() throws {
    let openAI = uniqueHost()
    let other = uniqueHost()
    try StudyCredentialStore.save(apiKey: "openai-key", host: openAI)

    XCTAssertNil(try StudyCredentialStore.apiKey(host: other))

    try StudyCredentialStore.delete(host: openAI)

    XCTAssertNil(try StudyCredentialStore.apiKey(host: openAI))
    XCTAssertNoThrow(try StudyCredentialStore.delete(host: openAI))
  }
}
