//
//  DeviceIDTests.swift
//  FoodTrackerTests
//
//  设备 ID 的测试：确认它真的存进了钥匙串，而且每次拿到的都是同一个。
//  测试跑在模拟器里的 App 上，用的是模拟器自己的钥匙串，不会碰到真手机上的数据。
//

import Foundation
import Testing

@testable import FoodTracker

// DeviceID 只能在主线程使用，所以整组测试标上 @MainActor
@MainActor
@Suite("设备 ID")
struct DeviceIDTests {
    @Test("存进钥匙串，每次拿到的都是同一个")
    func storedInKeychain() throws {
        let id = DeviceID.current
        // 是一个正常的随机 ID（UUID 的格式）
        #expect(UUID(uuidString: id) != nil)
        // 钥匙串里读出来的就是它
        #expect(DeviceID.readFromKeychain() == id)
        // 再拿一次还是同一个
        #expect(DeviceID.current == id)
        // 搬进钥匙串以后，旧版本存在 UserDefaults 里的那一份已经删掉了
        #expect(UserDefaults.standard.string(forKey: "deviceID") == nil)
    }
}
