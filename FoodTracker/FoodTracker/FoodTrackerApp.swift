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
        .modelContainer(for: AppModels.all) { result in
            // 数据库打不开时（多半是模型改法不对，见 FoodEntry.swift 开头的规则），SwiftUI 不会闪退，
            // 而是悄悄换成一个空的临时数据库：引导页会重新出现，而且什么都存不进去（原来的数据还在，只是没读出来）。
            // 开发版在这里直接停下，Xcode 里能看到原因；装到手机上的正式版不受影响
            if case .failure(let error) = result {
                assertionFailure("数据库打不开：\(error)")
            }
        }
    }
}

/// App 在手机上保存的所有数据类型。
/// 新加一种类型时加在这里：已有的数据不受影响（SwiftData 会自动升级数据库）
enum AppModels {
    static let all: [any PersistentModel.Type] = [UserProfile.self, FoodEntry.self]
}
