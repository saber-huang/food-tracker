//
//  DeviceID.swift
//  FoodTracker
//
//  设备 ID：第一次启动时随机生成一个，之后一直用同一个。
//  后端用它来统计每台设备每天用了几次，不包含任何个人信息。
//  第一版存在 UserDefaults 里（卸载重装会重新生成）；以后可以改存钥匙串，让它在重装后也不变。
//

import Foundation

enum DeviceID {
    private static let key = "deviceID"

    static let current: String = {
        if let saved = UserDefaults.standard.string(forKey: key) {
            return saved
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }()
}
