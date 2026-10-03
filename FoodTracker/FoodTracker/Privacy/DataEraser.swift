//
//  DataEraser.swift
//  FoodTracker
//
//  「删除所有数据」：删掉这台手机上的个人资料、全部饮食记录和所有设置
//  （热量提示、食谱偏好、上次的食谱、AI 功能的同意、徽章、没填完的引导进度），删完 App 回到第一次打开时的引导页。
//
//  不删的东西：钥匙串里的设备编号。它是随机的、和身份无关，只用来统计每天的使用次数；
//  删掉的话，每天的次数就能靠「删除所有数据」重新计算了（见 DeviceID.swift 和隐私政策）。
//

import Foundation
import SwiftData

enum DataEraser {
    /// - Parameters:
    ///   - defaults / defaultsDomain: 要清空的设置。App 里用默认值（整个 App 的 UserDefaults）；
    ///     单元测试传一个单独的 UserDefaults，免得清掉模拟器里 App 的真实设置
    static func eraseAll(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        defaultsDomain: String? = Bundle.main.bundleIdentifier
    ) throws {
        // AppModels.all 里的每一种数据都删：以后新加一种数据类型，这里自动跟着删
        for type in AppModels.all {
            try deleteAll(type, in: context)
        }
        try context.save()
        if let defaultsDomain {
            defaults.removePersistentDomain(forName: defaultsDomain)
        }
    }

    /// 删掉某一种数据的全部记录。一条一条删（而不是整批删），这样界面上的列表会马上跟着更新
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<T>()) {
            context.delete(item)
        }
    }
}
