//
//  ProductLog.swift
//  FoodTracker
//
//  几个匿名的产品指标：搜不到食物、用了 AI 估算、建了自定义食物、选了哪种份量单位……
//  只写进这台手机的系统日志（OSLog，用 Mac 上的「控制台」App 才看得到），不上传到任何地方。
//  以后要做统计（比如「最常搜不到的是什么」），从这里接出去就行。
//  不记用户输入的内容：搜索词只记有几个字；食物名字只在开发时看得到（OSLog 的 private 在正式版里会被隐藏）
//

import Foundation
import OSLog

nonisolated enum ProductLog {
    private static let logger = Logger(subsystem: "com.huangshengkai.FoodTracker", category: "product")

    enum Event: String {
        case foodSearchNoResult = "food_search_no_result"
        case aiFoodEstimateUsed = "ai_food_estimate_used"
        case customFoodCreated = "custom_food_created"
        case servingUnitSelected = "serving_unit_selected"
        case gramInputSelected = "gram_input_selected"
        case recentFoodSelected = "recent_food_selected"
        case frequentFoodSelected = "frequent_food_selected"
        case foodLogged = "food_logged"
        case labelScanned = "label_scanned"  // 拍营养成分表：detail 是认出了几项（0 = 没认出来）
    }

    /// 记一条。detail 是不含个人信息的补充（单位的 id、来源），name 只在开发时可见
    static func log(_ event: Event, detail: String = "", name: String? = nil) {
        if let name {
            logger.info("\(event.rawValue, privacy: .public) \(detail, privacy: .public) \(name, privacy: .private)")
        } else {
            logger.info("\(event.rawValue, privacy: .public) \(detail, privacy: .public)")
        }
    }
}
