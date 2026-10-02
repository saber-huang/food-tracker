//
//  CustomFood.swift
//  FoodTracker
//
//  「我的食物」：只存在这台手机上（SwiftData），和内置食物库分开；以后再搜同样的名字会排在最前面。三种来源：
//  - 包装食品（user）：照包装背面的营养成分表填的（每 100 克 / 每 100 毫升 / 每份，能量可以照抄千焦），
//    还可以填「一包多少克」，记录时直接选「1 包」「半包」
//  - AI 估算（ai）：搜不到的菜，AI 按名字估算后保存的
//  - 差不多的菜（similar）：搜不到、又不想用 AI 时，挑了一道食物库里差不多的菜，名字照用户写的
//  菜品没有营养成分表，谁也说不准一盘菜有几克脂肪，所以菜只能估算（AI 或差不多的菜），不让人手动填营养。
//
//  存法：「1 份」的营养（servingName / servingAmount / serving*），知道克数时换算成每 100 克去算别的份量：
//  - 每 100 克的营养成分表：1 份 = 100 克，没有「份」可选（只按克数，或者按下面的一包）
//  - 每份的营养成分表：1 份 = 表上的每份（每份多少克可以不知道，不知道就只能按份数记）
//  - AI 估算、差不多的菜：1 份 = 常见的一份；存的是正常做法的数字，油量每次记录时再选
//
//  ⚠️ 和 FoodEntry 一样，以后改这个类只能「加」不能「改」：新属性要可选或有默认值，选项存英文文字
//

import Foundation
import SwiftData

/// 我的食物从哪来
nonisolated enum CustomFoodSource: String, Sendable {
    case user  // 照包装填写（第七轮第一版：自己填写的）
    case ai  // AI 估算后保存
    case similar  // 选了一道差不多的菜
}

/// 营养成分表上的数字按什么写
nonisolated enum NutritionLabelBasis: String, Sendable {
    case per100  // 每 100 克 / 每 100 毫升
    case perServing  // 每份
}

@Model
final class CustomFood {
    var id: UUID = UUID()
    var name: String = ""
    var amountUnitRaw: String = AmountUnit.gram.rawValue  // 克还是毫升
    var servingName: String = ""  // 「1 份」的单位名；空 = 「份」
    var servingAmount: Double? = nil  // 1 份大约多少克（毫升）；nil = 不知道
    var servingKcal: Double = 0  // 1 份的营养（AI 估算、差不多的菜：正常做法）
    var servingProteinG: Double = 0
    var servingCarbsG: Double = 0
    var servingFatG: Double = 0
    var sourceRaw: String = CustomFoodSource.user.rawValue
    var createdAt: Date = Date.now
    var lastUsedAt: Date? = nil  // 最近一次用到（新建也算一次）：「我的食物」按它排

    // 第七轮第二版加的（都是可选的）
    var labelBasisRaw: String? = nil  // 照包装填写：营养成分表按什么写（NutritionLabelBasis）
    var packageName: String? = nil  // 一包的单位：PackageUnit 的 id（pack、bottle……）
    var packageAmount: Double? = nil  // 一包多少克（毫升）
    var foodTypeRaw: String? = nil  // dish 现做的菜 / packaged 包装食品 / other：菜才能选油量
    var basedOnRef: String? = nil  // 差不多的菜：按食物库里哪一道估算的（catalog:pork_pepper）

    typealias Source = CustomFoodSource

    init(
        name: String, amountUnit: AmountUnit = .gram, servingName: String, servingAmount: Double?,
        servingValues: NutrientValues, source: Source, createdAt: Date = .now, labelBasis: NutritionLabelBasis? = nil,
        packageName: String? = nil, packageAmount: Double? = nil, foodType: EstimatedFoodType? = nil,
        basedOnRef: String? = nil
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
        self.labelBasisRaw = labelBasis?.rawValue
        self.packageName = packageName
        self.packageAmount = packageAmount
        self.foodTypeRaw = foodType?.rawValue
        self.basedOnRef = basedOnRef
    }

    var amountUnit: AmountUnit { AmountUnit(storedValue: amountUnitRaw) }
    var source: CustomFoodSource { CustomFoodSource(rawValue: sourceRaw) ?? .user }
    var labelBasis: NutritionLabelBasis? { labelBasisRaw.flatMap(NutritionLabelBasis.init(rawValue:)) }

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

    /// 照包装填写的表单存下来（新建和修改都用它）
    func apply(_ label: LabelFoodFields) {
        name = label.name
        amountUnitRaw = label.amountUnit.rawValue
        servingName = ""
        servingAmount = label.servingAmount
        servingValues = label.servingValues
        labelBasisRaw = label.basis.rawValue
        packageName = label.packageName
        packageAmount = label.packageAmount
        foodTypeRaw = EstimatedFoodType.packaged.rawValue
    }

    /// 搜索、份量页用的样子
    var snapshot: CustomFoodSnapshot {
        CustomFoodSnapshot(
            id: id, name: name, amountUnit: amountUnit, servingName: servingName, servingAmount: servingAmount,
            servingValues: servingValues, source: source, labelBasis: labelBasis, packageName: packageName,
            packageAmount: packageAmount, foodType: foodTypeRaw.flatMap(EstimatedFoodType.init(rawValue:)),
            basedOnRef: basedOnRef, lastUsedAt: lastUsedAt)
    }

    /// 最近用过（或刚建好）的排前面：「我的食物」列表的先后
    static var recentFirst: FetchDescriptor<CustomFood> {
        FetchDescriptor(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)])
    }
}

extension CustomFood {
    /// 照包装新建一种我的食物
    static func fromLabel(_ label: LabelFoodFields) -> CustomFood {
        let food = CustomFood(name: label.name, servingName: "", servingAmount: nil, servingValues: .zero, source: .user)
        food.apply(label)
        return food
    }
}
