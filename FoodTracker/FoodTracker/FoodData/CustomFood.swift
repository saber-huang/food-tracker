//
//  CustomFood.swift
//  FoodTracker
//
//  「我的食物」：用户自己建的食物（「妈妈做的红烧肉 · 1 份约 220 克 · 560 千卡」），或者 AI 估算后确认保存的食物。
//  只存在这台手机上（SwiftData），和内置食物库分开：AI 估算的结果只进这里，不会变成所有人共享的数据。
//  以后再搜同样的名字，会排在最前面，不用每次重新让 AI 估算。
//
//  按用户填写的样子存「1 份」：份量的名字（默认「份」）、1 份多少克（可以不填）、1 份的热量和营养。
//  知道克数时，换算成「每 100 克」去算别的份量；不知道克数就按份数乘。
//
//  ⚠️ 和 FoodEntry 一样，以后改这个类只能「加」不能「改」：新属性要可选或有默认值，选项存英文文字
//  （以后想支持「我的饭碗 ≈ 180 克」这类自定义份量，另外加一张表，用 foodRef 关联到这里或食物库）
//

import Foundation
import SwiftData

@Model
final class CustomFood {
    var id: UUID = UUID()
    var name: String = ""
    var amountUnitRaw: String = AmountUnit.gram.rawValue  // 克还是毫升
    var servingName: String = ""  // 参考份量的单位名：「份」「碗」「盒」……空 = 「份」
    var servingAmount: Double? = nil  // 1 份大约多少克（毫升）；nil = 不知道
    var servingKcal: Double = 0  // 1 份的营养
    var servingProteinG: Double = 0
    var servingCarbsG: Double = 0
    var servingFatG: Double = 0
    var sourceRaw: String = Source.user.rawValue
    var createdAt: Date = Date.now
    var lastUsedAt: Date? = nil  // 最近一次用到（新建也算一次）：「我的食物」按它排

    /// 是用户自己填的，还是 AI 估算后保存的
    enum Source: String {
        case user, ai
    }

    init(
        name: String, amountUnit: AmountUnit = .gram, servingName: String, servingAmount: Double?,
        servingValues: NutrientValues, source: Source, createdAt: Date = .now
    ) {
        self.id = UUID()
        self.name = name
        self.amountUnitRaw = amountUnit.rawValue
        self.servingName = servingName
        self.servingAmount = servingAmount
        self.servingKcal = servingValues.caloriesKcal
        self.servingProteinG = servingValues.proteinG
        self.servingCarbsG = servingValues.carbsG
        self.servingFatG = servingValues.fatG
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.lastUsedAt = createdAt
    }

    var amountUnit: AmountUnit { AmountUnit(storedValue: amountUnitRaw) }

    var servingValues: NutrientValues {
        get {
            NutrientValues(caloriesKcal: servingKcal, proteinG: servingProteinG, carbsG: servingCarbsG, fatG: servingFatG)
        }
        set {
            servingKcal = newValue.caloriesKcal
            servingProteinG = newValue.proteinG
            servingCarbsG = newValue.carbsG
            servingFatG = newValue.fatG
        }
    }

    /// 搜索、份量页用的样子
    var snapshot: CustomFoodSnapshot {
        CustomFoodSnapshot(
            id: id, name: name, amountUnit: amountUnit, servingName: servingName, servingAmount: servingAmount,
            servingValues: servingValues, isAIEstimate: sourceRaw == Source.ai.rawValue, lastUsedAt: lastUsedAt)
    }

    /// 最近用过（或刚建好）的排前面：「我的食物」列表的先后
    static var recentFirst: FetchDescriptor<CustomFood> {
        FetchDescriptor(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)])
    }
}
