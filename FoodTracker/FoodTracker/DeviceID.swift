//
//  DeviceID.swift
//  FoodTracker
//
//  设备 ID：第一次启动时随机生成一个，之后一直用同一个。
//  后端用它来统计每台设备每天用了几次，不包含任何个人信息。
//
//  存在「钥匙串」（Keychain）里，而不是普通的设置（UserDefaults）里：
//  删掉 App 再装回来，一般还能读到同一个 ID，每天的次数不会因为重装而重新计算。
//  只留在这台手机上：不跟 iCloud 钥匙串同步，也不随备份搬到新手机（每台设备各算各的次数）。
//  以前的版本存在 UserDefaults 里，第一次运行新版本时会搬过来，ID 保持不变。
//

import Foundation
import Security

enum DeviceID {
    private static let service = Bundle.main.bundleIdentifier ?? "FoodTracker"
    private static let account = "deviceID"
    /// 以前的版本存在 UserDefaults 里用的名字
    private static let legacyDefaultsKey = "deviceID"

    static let current: String = {
        if let saved = readFromKeychain() {
            return saved
        }
        // 钥匙串里还没有：优先沿用以前存在 UserDefaults 里的 ID，没有就新生成一个
        let id = UserDefaults.standard.string(forKey: legacyDefaultsKey) ?? UUID().uuidString
        if saveToKeychain(id) {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        } else {
            // 钥匙串存不进去（很少见）：先放在 UserDefaults 里，下次启动再试着搬
            UserDefaults.standard.set(id, forKey: legacyDefaultsKey)
        }
        return id
    }()

    /// 钥匙串里的这一项：按 App 的包名和「deviceID」这个名字找
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 从钥匙串读出设备 ID；没有就是 nil（单元测试也用它确认真的存进去了）
    static func readFromKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data,
            let id = String(data: data, encoding: .utf8), !id.isEmpty
        else { return nil }
        return id
    }

    private static func saveToKeychain(_ id: String) -> Bool {
        let data = Data(id.utf8)
        var query = baseQuery
        query[kSecValueData as String] = data
        // 手机开机解锁过一次之后就能读（App 在后台时也能用）；ThisDeviceOnly = 只留在这台手机上
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // 已经有这一项却读不出来（比如内容坏了）：用新的 ID 覆盖，下次就能读到
            let update = [kSecValueData as String: data]
            return SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        return status == errSecSuccess
    }
}
