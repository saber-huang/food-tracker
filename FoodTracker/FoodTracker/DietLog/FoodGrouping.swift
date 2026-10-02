//
//  FoodGrouping.swift
//  FoodTracker
//
//  两件和「同一种食物」有关的事，都只影响显示和填写，不改存下来的数据：
//  1. 合并显示：同一餐里重复记了几次的同一种食物，「今日」里显示成一行「米饭 ×2  348 千卡」，
//     点开还能看到、修改每一条。数据库里仍然是一条一条的记录
//  2. 最近使用：手动添加时，从以前的记录里挑出最近吃过的食物，点一下就填好名字（和上次的份量、营养）
//
//  「同一种食物」怎么判断（不能只比字符串）：
//  - 名字规范化后一样：去掉空格和标点、全角换成半角、英文不分大小写（「米饭」「米饭 」「Rice」「rice」）
//  - 份量差不多：两条都没填份量，或者相差不超过 10%
//  - 热量差不多：相差不超过 10%（或不超过 10 千卡）
//  名字一样但份量、热量明显不同（比如一小碗和一大碗）就不合并。只在同一餐里合并（由调用的地方按餐分好）
//

import Foundation

/// 名字规范化：比较两个名字是不是同一种食物时用
nonisolated enum FoodNameKey {
    static func normalize(_ name: String) -> String {
        name.precomposedStringWithCompatibilityMapping  // 全角字母、数字 → 半角（ＲＩＣＥ → RICE）
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
    }
}

/// 参与比较的一条记录：只需要名字、份量和热量（不依赖数据库，方便测试）
nonisolated struct GroupingItem: Equatable {
    let name: String
    let weightG: Double?
    let caloriesKcal: Double
}

nonisolated enum FoodGrouping {
    /// 两条记录是不是「同一种食物、差不多的量」
    static func isSameFood(_ a: GroupingItem, _ b: GroupingItem) -> Bool {
        guard FoodNameKey.normalize(a.name) == FoodNameKey.normalize(b.name) else { return false }
        return isClose(a.weightG, b.weightG) && isClose(a.caloriesKcal, b.caloriesKcal, absolute: 10)
    }

    /// 按出现的先后分组：返回每一组里的下标。组的顺序按每组第一条出现的先后，组里也按先后。
    /// 每条只和每组的第一条比（第一条代表这一组），不会因为一点点差别连成一长串
    static func groups(_ items: [GroupingItem]) -> [[Int]] {
        var result: [[Int]] = []
        for (index, item) in items.enumerated() {
            if let group = result.firstIndex(where: { isSameFood(items[$0[0]], item) }) {
                result[group].append(index)
            } else {
                result.append([index])
            }
        }
        return result
    }

    /// 两个份量（可能没填）差不多：都没填算一样；只有一个填了不算
    private static func isClose(_ a: Double?, _ b: Double?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case (let x?, let y?): isClose(x, y, absolute: 1)
        default: false
        }
    }

    /// 两个数差不多：相差不超过 10%，或者不超过 absolute（数字很小时用）
    private static func isClose(_ a: Double, _ b: Double, absolute: Double) -> Bool {
        let gap = abs(a - b)
        return gap <= absolute || gap <= 0.1 * max(abs(a), abs(b))
    }
}

/// 「最近使用」里的一种食物：名字，和最近一次记录时的份量、营养（点了用来预填，用户可以再改）
nonisolated struct RecentFood: Identifiable, Hashable, Sendable {
    let name: String
    let weightG: Double?  // 克（或毫升，见 amountUnit）
    let values: NutrientValues
    var amountUnit: AmountUnit = .gram
    var servingQuantity: Double? = nil  // 上次选的自然份量：几份、哪个单位
    var servingUnitID: String? = nil
    var foodRef: String? = nil  // 来自哪种食物
    var loggedAt: Date? = nil  // 什么时候记的（算「常吃」用）
    var oilLevel: OilLevel? = nil  // 上次选的油量（家常菜）

    var id: String { FoodNameKey.normalize(name) }
}

nonisolated enum RecentFoods {
    /// 从记录里挑出不重复的食物。records 要按时间从新到旧排好；每种食物只留最近的那一次
    static func from(_ records: [RecentFood], limit: Int = 30) -> [RecentFood] {
        var seen = Set<String>()
        var result: [RecentFood] = []
        for record in records where !record.id.isEmpty && seen.insert(record.id).inserted {
            result.append(record)
            if result.count == limit { break }
        }
        return result
    }

    /// 常吃：最近 days 天里记了至少 minCount 次的食物，次数多的在前（每种给最近一次的份量）。
    /// 自动算出来，不用用户手动收藏。records 要按时间从新到旧排好
    static func frequent(
        _ records: [RecentFood], now: Date, days: Int = 30, minCount: Int = 3, limit: Int = 8
    ) -> [RecentFood] {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        var counts: [String: Int] = [:]
        var latest: [String: RecentFood] = [:]
        var order: [String] = []
        for record in records where !record.id.isEmpty {
            guard let date = record.loggedAt, date >= start else { continue }
            counts[record.id, default: 0] += 1
            if latest[record.id] == nil {
                latest[record.id] = record
                order.append(record.id)
            }
        }
        let firstSeen = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return order
            .filter { (counts[$0] ?? 0) >= minCount }
            .sorted { (counts[$0] ?? 0, -(firstSeen[$0] ?? 0)) > (counts[$1] ?? 0, -(firstSeen[$1] ?? 0)) }
            .prefix(limit)
            .compactMap { latest[$0] }
    }

    /// 输入框里打了字时，挑出名字里含有这些字的；名字一模一样的排最前，开头一样的其次。
    /// 什么都没打时就是最近吃过的几种
    static func matching(_ foods: [RecentFood], query: String, limit: Int = 8) -> [RecentFood] {
        let key = FoodNameKey.normalize(query)
        guard !key.isEmpty else { return Array(foods.prefix(limit)) }
        let hits = foods.filter { $0.id.contains(key) }
        let exact = hits.filter { $0.id == key }
        let prefix = hits.filter { $0.id != key && $0.id.hasPrefix(key) }
        let rest = hits.filter { !$0.id.hasPrefix(key) }
        return Array((exact + prefix + rest).prefix(limit))
    }
}
