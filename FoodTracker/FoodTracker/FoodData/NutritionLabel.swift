//
//  NutritionLabel.swift
//  FoodTracker
//
//  照包装背面的营养成分表填写「我的食物」：表单里填的样子 → 存进数据库的样子。
//  只有包装食品（饮料、零食、速冻食品……）才有准确的营养成分表；菜品走 AI 估算或「差不多的菜」。
//  - 表上按什么写：每 100 克 / 每 100 毫升 / 每份（每份多少克可以不知道）
//  - 能量照抄：中国的包装一般写千焦（kJ），换算成千卡（1 千卡 = 4.184 千焦）；美国的包装写 Calories（就是千卡）
//  - 营养素的顺序和中国的营养成分表一样：能量、蛋白质、脂肪、碳水化合物
//  - 一包多少克（净含量）可以不填；填了以后记录时可以按「1 包」「半包」选
//  这里不碰界面和数据库，方便单元测试
//

import Foundation

/// 能量的单位：中国的营养成分表写千焦，美国的写 Calories（千卡）
nonisolated enum EnergyUnit: String, CaseIterable, Hashable, Sendable {
    case kilojoule, kilocalorie

    static let kilojoulesPerKcal = 4.184

    var symbol: String {
        switch self {
        case .kilojoule: String(localized: "千焦")
        case .kilocalorie: String(localized: "千卡")
        }
    }

    /// 换算成千卡
    func kcal(_ value: Double) -> Double {
        self == .kilojoule ? value / Self.kilojoulesPerKcal : value
    }

    /// 打开修改时：存的是千卡，按这个单位显示
    func value(fromKcal kcal: Double) -> Double {
        self == .kilojoule ? kcal * Self.kilojoulesPerKcal : kcal
    }

    /// 默认用哪个：中文界面多半是中国的包装（千焦），英文界面多半是千卡
    static var preferred: EnergyUnit { AppLanguage.current == .zh ? .kilojoule : .kilocalorie }
}

/// 营养成分表的那一列写的是什么
nonisolated enum LabelColumn: String, CaseIterable, Hashable, Sendable {
    case per100g, per100ml, perServing

    var title: String {
        switch self {
        case .per100g: String(localized: "每 100 克")
        case .per100ml: String(localized: "每 100 毫升")
        case .perServing: String(localized: "每份")
        }
    }
}

/// 一包的单位：从这几个里选（不让人随便打字：第一版打了数字「1」，标题就成了「11大约」）
nonisolated struct PackageUnit: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let nameEn: String
    let nameEnPlural: String

    var displayName: String { AppLanguage.current == .en ? nameEn : name }

    /// 记录时可以选的「1 包」（一包多少克由用户填）
    func servingUnit(amount: Double) -> ServingUnit {
        ServingUnit(id: "package", name: name, nameEn: nameEn, nameEnPlural: nameEnPlural, amount: amount, step: 0.5)
    }

    static let all: [PackageUnit] = [
        PackageUnit(id: "pack", name: "包", nameEn: "pack", nameEnPlural: "packs"),
        PackageUnit(id: "bottle", name: "瓶", nameEn: "bottle", nameEnPlural: "bottles"),
        PackageUnit(id: "can", name: "罐", nameEn: "can", nameEnPlural: "cans"),
        PackageUnit(id: "box", name: "盒", nameEn: "box", nameEnPlural: "boxes"),
        PackageUnit(id: "bag", name: "袋", nameEn: "bag", nameEnPlural: "bags"),
        PackageUnit(id: "cup", name: "杯", nameEn: "cup", nameEnPlural: "cups"),
        PackageUnit(id: "bar", name: "支", nameEn: "bar", nameEnPlural: "bars"),
        PackageUnit(id: "piece", name: "块", nameEn: "piece", nameEnPlural: "pieces"),
        PackageUnit(id: "item", name: "个", nameEn: "item", nameEnPlural: "items"),
        PackageUnit(id: "slice", name: "片", nameEn: "slice", nameEnPlural: "slices"),
    ]

    static func named(_ id: String?) -> PackageUnit? { all.first { $0.id == id } }
}

/// 存进「我的食物」的样子（CustomFood.apply 用）
nonisolated struct LabelFoodFields: Hashable, Sendable {
    var name: String
    var basis: NutritionLabelBasis
    var amountUnit: AmountUnit
    var servingAmount: Double?  // 每 100 克的表：100；每份的表：每份多少克，可以不知道
    var servingValues: NutrientValues  // 「1 份」的营养（千卡）
    var packageName: String?
    var packageAmount: Double?
}

/// 表单里填的内容（数字已经从文字换成数，没填是 nil）
nonisolated struct NutritionLabelInput: Hashable, Sendable {
    var name: String
    var column: LabelColumn = .per100g
    var servingUnit: AmountUnit = .gram  // 每份的表：每份按克还是毫升
    var servingSize: Double?  // 每份的表：每份多少克（毫升）
    var energy: Double?
    var energyUnit: EnergyUnit = .preferred
    var protein: Double?
    var fat: Double?
    var carbs: Double?
    var packageID: String = PackageUnit.all[0].id
    var packageAmount: Double?

    /// 每 100 克的表最多约 900 千卡（纯油 884）；每份最多 5000 千卡（再多多半是单位填错了）
    static let maxKcalPer100 = 900.0
    static let maxKcalPerServing = 5000.0

    var basis: NutritionLabelBasis { column == .perServing ? .perServing : .per100 }

    /// 克还是毫升
    var amountUnit: AmountUnit {
        switch column {
        case .per100g: .gram
        case .per100ml: .milliliter
        case .perServing: servingUnit
        }
    }

    /// 能量换算成千卡
    var kcal: Double? { energy.map { energyUnit.kcal($0) } }

    /// 每份的表又不知道每份多重：没法换算「一包」，那一项先不让填
    var canUsePackage: Bool { column != .perServing || (servingSize ?? 0) > 0 }

    // MARK: - 检查（只检查填了的；名称和能量必填）

    var nameError: String? { EntryValidator.nameError(name) }

    var energyError: String? {
        guard let kcal else { return nil }  // 没填：保存时再提示
        if kcal <= 0 { return String(localized: "能量要大于 0") }
        if basis == .per100, kcal > Self.maxKcalPer100 {
            return String(localized: "每 100 克（毫升）不会超过约 900 千卡（3766 千焦），请检查单位")
        }
        if kcal > Self.maxKcalPerServing { return String(localized: "数字太大了，请检查单位") }
        return nil
    }

    /// 蛋白质、脂肪、碳水加起来不能比这一份还重
    var macrosError: String? {
        let total = (protein ?? 0) + (fat ?? 0) + (carbs ?? 0)
        let limit: Double? = basis == .per100 ? 100 : servingSize
        guard let limit, limit > 0, total > limit + 0.05 else { return nil }
        return String(localized: "蛋白质、脂肪、碳水加起来比这一份还重，请检查单位")
    }

    var isComplete: Bool {
        nameError == nil && kcal != nil && energyError == nil && macrosError == nil
    }

    // MARK: - 换算成存进去的样子

    var fields: LabelFoodFields? {
        guard isComplete, let kcal else { return nil }
        let values = DietLogMath.rounded(
            NutrientValues(caloriesKcal: kcal, proteinG: protein ?? 0, carbsG: carbs ?? 0, fatG: fat ?? 0))
        let package = canUsePackage ? packageAmount.flatMap { $0 > 0 ? DietLogMath.round1($0) : nil } : nil
        return LabelFoodFields(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            basis: basis,
            amountUnit: amountUnit,
            servingAmount: basis == .per100 ? 100 : servingSize.flatMap { $0 > 0 ? DietLogMath.round1($0) : nil },
            servingValues: values,
            packageName: package == nil ? nil : packageID,
            packageAmount: package)
    }
}

extension NutritionLabelInput {
    /// 打开修改：把存下来的样子放回表单（能量按千卡显示）
    init(food: CustomFoodSnapshot) {
        self.init(name: food.name)
        let isPer100 = food.labelBasis == .per100
        column = isPer100 ? (food.amountUnit == .milliliter ? .per100ml : .per100g) : .perServing
        servingUnit = food.amountUnit
        servingSize = isPer100 ? nil : food.servingAmount
        energy = food.servingValues.caloriesKcal
        energyUnit = .kilocalorie
        protein = food.servingValues.proteinG
        fat = food.servingValues.fatG
        carbs = food.servingValues.carbsG
        if let id = food.packageName, PackageUnit.named(id) != nil { packageID = id }
        packageAmount = food.packageAmount
    }
}
