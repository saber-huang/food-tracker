//
//  AppConfig.swift
//  FoodTracker
//
//  App 的配置，目前只有后端地址。
//

import Foundation

enum AppConfig {
    /// 后端地址：模拟器和真机访问电脑的方式不一样，这里自动选择
    static let backendURL: URL = {
        #if targetEnvironment(simulator)
        // 模拟器和电脑共用网络，127.0.0.1 指的就是这台电脑自己
        return URL(string: "http://127.0.0.1:8000")!
        #else
        // 真机要通过 Wi-Fi 找到电脑，用的是电脑的「本地主机名」加 .local。
        // 前提：手机和电脑连同一个 Wi-Fi，后端用 --host 0.0.0.0 启动。
        return URL(string: "http://huangdeMacBook-Pro.local:8000")!
        #endif
    }()
}
