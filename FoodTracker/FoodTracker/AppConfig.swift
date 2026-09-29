//
//  AppConfig.swift
//  FoodTracker
//
//  App 的配置：后端地址和 App 密钥。
//  两个值都来自 Config/Secrets.xcconfig（不上传 GitHub）→ 编译时写进 Info.plist → 这里读出来。
//

import Foundation

enum AppConfig {
    /// Info.plist 里的一个文字值；没有或为空时返回 nil
    private static func plistString(_ key: String) -> String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// 后端地址。Secrets.xcconfig 里填了 BACKEND_URL 就用它（云端）；
    /// 没填就连电脑上的本地后端：模拟器和真机访问电脑的方式不一样，这里自动选择。
    static let backendURL: URL = {
        if let text = plistString("BackendURL"), let url = URL(string: text) {
            return url
        }
        #if targetEnvironment(simulator)
        // 模拟器和电脑共用网络，127.0.0.1 指的就是这台电脑自己
        return URL(string: "http://127.0.0.1:8000")!
        #else
        // 真机要通过 Wi-Fi 找到电脑，用的是电脑的「本地主机名」加 .local。
        // 前提：手机和电脑连同一个 Wi-Fi，后端用 --host 0.0.0.0 启动。
        return URL(string: "http://huangdeMacBook-Pro.local:8000")!
        #endif
    }()

    /// App 密钥：每个请求都会带上，后端用它挡住随手乱试的人。本地开发时为空，后端也不检查
    static let appKey: String = plistString("AppKey") ?? ""

    /// 现在连的是不是云端后端（云端一定是 https）
    static var isCloud: Bool { backendURL.scheme == "https" }
}
