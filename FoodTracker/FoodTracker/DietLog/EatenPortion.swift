//
//  EatenPortion.swift
//  FoodTracker
//
//  没吃完：一样食物吃了几成（全部、¾、一半、¼、没吃）。
//  记录里存的热量、营养素一直是「吃下去的」，所以合计、日历、统计都不用改；
//  另外记住「原来盛了多少」（ServedPortion），改回「全部吃完」时原样换回去，不会越乘越小。
//  只做计算和文字，不涉及界面和存储，可以单独写单元测试（FoodTrackerTests/EatenPortionTests.swift）
//

import Foundation

nonisolated enum EatenPortion {
    /// 整餐能选的几档（「这餐吃了多少」）：全部、¾、一半、¼
    static let mealOptions: [Double] = [1, 0.75, 0.5, 0.25]
    /// 每一样能选的几档：多一个「没吃」（保存时从这餐里删掉）
    static let itemOptions: [Double] = [1, 0.75, 0.5, 0.25, 0]

    /// 换成最接近的一档（AI 估算的 0.6 → 0.5，0.9 → 1）。正好在两档中间时取多的那一档：宁可多算一点，不少算
    static func snapped(_ fraction: Double) -> Double {
        guard fraction.isFinite else { return 1 }
        let clamped = min(max(fraction, 0), 1)
        return itemOptions.min { a, b in
            let da = abs(a - clamped), db = abs(b - clamped)
            return da == db ? a > b : da < db
        } ?? 1
    }

    /// 吃下去的营养 = 原来的 × 吃了几成（热量取整，营养素保留 1 位小数，和存进记录的规则一样）
    static func eatenValues(served: NutrientValues, fraction: Double) -> NutrientValues {
        DietLogMath.rounded(
            NutrientValues(
                caloriesKcal: served.caloriesKcal * fraction, proteinG: served.proteinG * fraction,
                carbsG: served.carbsG * fraction, fatG: served.fatG * fraction))
    }

    /// 吃下去的重量（保留 1 位小数）；不知道原来多重时是 nil
    static func eatenWeight(served: Double?, fraction: Double) -> Double? {
        served.map { DietLogMath.round1($0 * fraction) }
    }

    // MARK: - 文字

    /// 整餐的分段按钮上的字：「全部」「¾」「一半」「¼」
    static func mealLabel(_ fraction: Double) -> String {
        switch fraction {
        case 1: String(localized: "全部")
        case 0.75: String(localized: "¾")
        case 0.5: String(localized: "一半")
        case 0.25: String(localized: "¼")
        default: percent(fraction)
        }
    }

    /// 每一样的选项、记录上的小标签：「全部吃完」「吃了¾」「吃了一半」「吃了¼」「没吃」
    static func itemLabel(_ fraction: Double) -> String {
        switch fraction {
        case 1: String(localized: "全部吃完")
        case 0.75: String(localized: "吃了¾")
        case 0.5: String(localized: "吃了一半")
        case 0.25: String(localized: "吃了¼")
        case 0: String(localized: "没吃")
        default: String(localized: "吃了 \(percent(fraction))")
        }
    }

    /// 旁白读的：「¾」读成「四分之三」，不读「分数」
    static func spokenItemLabel(_ fraction: Double) -> String {
        switch fraction {
        case 0.75: String(localized: "吃了四分之三")
        case 0.25: String(localized: "吃了四分之一")
        default: itemLabel(fraction)
        }
    }

    static func spokenMealLabel(_ fraction: Double) -> String {
        switch fraction {
        case 0.75: String(localized: "四分之三")
        case 0.25: String(localized: "四分之一")
        default: mealLabel(fraction)
        }
    }

    /// 不在几档里的比例（以后的数据、测试）：「60%」
    private static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// 没吃完的记录记下的「原来盛了多少」：改回全部吃完时原样换回去
nonisolated struct ServedPortion: Equatable {
    var weightG: Double?
    var values: NutrientValues
    var servingQuantity: Double?
}
