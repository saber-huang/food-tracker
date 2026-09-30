//
//  FoodTrackerApp.swift
//  FoodTracker
//
//  Created by huang shengkai on 9/28/26.
//

import SwiftData
import SwiftUI

@main
struct FoodTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()  // 没有资料时显示引导流程，有资料时显示主界面
        }
        // 告诉 SwiftData 要保存哪些数据；数据存在手机本地
        .modelContainer(for: AppModels.all)
    }
}

/// App 在手机上保存的所有数据类型。
/// 新加一种类型时加在这里：已有的数据不受影响（SwiftData 会自动升级数据库）
enum AppModels {
    static let all: [any PersistentModel.Type] = [UserProfile.self, FoodEntry.self]
}
