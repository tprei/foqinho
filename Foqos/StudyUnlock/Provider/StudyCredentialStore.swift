import Foundation
import Security

enum StudyCredentialStore {
  struct KeychainError: Error, Equatable {
    let status: OSStatus
  }

  static let service = "dev.ambitionsoftware.foqos.study-provider"

  static func save(apiKey: String, host: String) throws {
    let data = Data(apiKey.utf8)
    let status = SecItemUpdate(
      query(host: host) as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    switch status {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var item = query(host: host)
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      try check(SecItemAdd(item as CFDictionary, nil))
    default:
      throw KeychainError(status: status)
    }
  }

  static func apiKey(host: String) throws -> String? {
    var request = query(host: host)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    guard status != errSecItemNotFound else { return nil }
    try check(status)
    guard let data = result as? Data else { throw KeychainError(status: errSecDecode) }
    return String(decoding: data, as: UTF8.self)
  }

  static func delete(host: String) throws {
    let status = SecItemDelete(query(host: host) as CFDictionary)
    guard status != errSecItemNotFound else { return }
    try check(status)
  }

  private static func query(host: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: host,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private static func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }
}
