//
//  FoodChoice.swift
//  FoodTracker
//
//  选中一种食物、准备记录时用的东西：
//  - FoodChoice：一种食物 + 它的营养基准 + 能选的份量单位。食物库、我的食物、最近吃过、AI 估算点进去都先变成它，
//    再交给份量页（FoodServingView）
//  - ServingMath：「1.5 碗」→ 225 克 → 营养。自然份量先换成克（毫升），再用 DietLogMath.scaled 按克算，
//    和手动填写是同一套计算；只知道「1 份多少千卡」、不知道多重的食物，按份数乘
//  - PortionText：份量怎么写给人看（「半碗」「1.5 碗」「约 150 克」）
//  估算的数字（AI 估算、按做法估算的家常菜）不假装精确：热量取整到 10、营养素取整到 1 克，前面写「约」
//

import Foundation

/// 营养按什么算
nonisolated enum NutritionBasis: Hashable, Sendable {
    /// 每 100 克（或毫升）多少：选份量时按重量换算
    case per100(NutrientValues, AmountUnit)
    /// 只知道 1 份多少、不知道多重：按份数乘
    case perServing(NutrientValues)

    /// 按重量算时用克还是毫升；只按份数算时是 nil（没有「克」可选）
    var amountUnit: AmountUnit? {
        if case .per100(_, let unit) = self { return unit }
        return nil
    }
}

/// 记录里存的「选了哪个自然份量」：单位的 id、当时显示的名字、几份
nonisolated struct ServingChoice: Hashable, Sendable {
    var unitID: String
    var unitName: String
    var quantity: Double
}

/// 份量页上选的是什么：某个自然单位的几份，或者直接填克数（毫升）
nonisolated enum ServingSelection: Hashable, Sendable {
    case natural(unitID: String, quantity: Double)
    case amount(Double?)  // 填的克数；nil = 还没填
}

/// 准备记录的一种食物
nonisolated struct FoodChoice: Identifiable, Hashable, Sendable {
    enum Origin: Hashable, Sendable {
        case catalog(String)
        case custom(UUID)
        case recent
        case aiEstimate
    }

    let id: String
    let name: String
    let origin: Origin
    let basis: NutritionBasis
    /// 这种食物的自然份量单位（碗、个……）。按重量算的食物另外总能选「克 / 毫升」
    let units: [ServingUnit]
    /// 打开时选中什么（上次吃了多少，或者常见的 1 份）
    let initialSelection: ServingSelection
    /// 数字是估算的：AI 估算、按常见做法估算的家常菜
    let isEstimate: Bool
    /// 存进记录的来源标记（catalog:rice、custom:<UUID>）；最近吃过的随手记录、AI 估算还没保存时是 nil
    let foodRef: String?

    var isAIEstimate: Bool { origin == .aiEstimate }
    var isMine: Bool { if case .custom = origin { return true } else { return false } }

    func unit(id: String) -> ServingUnit? { units.first { $0.id == id } }
}

// MARK: - 份量 → 营养

nonisolated enum ServingMath {
    /// 两个份量差不到 2% 就当作一样（判断「150 克是不是正好 1 碗」用）
    private static let tolerance = 0.02

    /// 这样选一共多少克（毫升）；按份数算、不知道重量时是 nil
    static func amount(of selection: ServingSelection, in choice: FoodChoice) -> Double? {
        switch selection {
        case .natural(let unitID, let quantity):
            guard let unit = choice.unit(id: unitID), unit.amount > 0 else { return nil }
            return quantity * unit.amount
        case .amount(let grams):
            return grams
        }
    }

    /// 这样选的营养（没有取整）。按重量算的食物用 DietLogMath.scaled，和手动填写换算的是同一套公式
    static func values(of selection: ServingSelection, in choice: FoodChoice) -> NutrientValues {
        switch choice.basis {
        case .per100(let per100, _):
            guard let grams = amount(of: selection, in: choice) else { return .zero }
            return DietLogMath.scaled(per100, toWeightG: grams)
        case .perServing(let perServing):
            guard case .natural(_, let quantity) = selection else { return .zero }
            return NutrientValues(
                caloriesKcal: perServing.caloriesKcal * quantity, proteinG: perServing.proteinG * quantity,
                carbsG: perServing.carbsG * quantity, fatG: perServing.fatG * quantity)
        }
    }

    /// 克数换回自然份量：正好是步长的整数倍（差不到 2%）才换，比如 150 克 = 1 碗、225 克 = 1.5 碗；
    /// 180 克米饭就不硬说成「1.2 碗」，仍然按克显示
    static func quantity(forAmount grams: Double, unit: ServingUnit) -> Double? {
        guard unit.amount > 0, grams > 0 else { return nil }
        let steps = (grams / unit.amount / unit.step).rounded()
        guard steps >= 1 else { return nil }
        let quantity = steps * unit.step
        return abs(quantity * unit.amount - grams) <= tolerance * grams ? quantity : nil
    }

    /// 估算的数字取整（不假装精确）：热量到 10 千卡、营养素到 1 克；准确的数字照常（热量整数、营养素 1 位小数）
    static func displayed(_ values: NutrientValues, isEstimate: Bool) -> NutrientValues {
        guard isEstimate else { return DietLogMath.rounded(values) }
        return NutrientValues(
            caloriesKcal: (values.caloriesKcal / 10).rounded() * 10,
            proteinG: values.proteinG.rounded(), carbsG: values.carbsG.rounded(), fatG: values.fatG.rounded())
    }

    /// 加减按钮：在步长上加一步 / 减一步，最少一步、最多 99
    static func stepped(_ quantity: Double, by direction: Int, step: Double) -> Double {
        let next = ((quantity / step).rounded() + Double(direction)) * step
        return min(max(next, step), 99)
    }
}

// MARK: - 份量写给人看

nonisolated enum PortionText {
    /// 数量：1、1.5、2（不写多余的 0）
    static func number(_ quantity: Double) -> String {
        quantity.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// 「半碗」「1 碗」「1.5 碗」；英文 "½ bowl"、"1.5 bowls"
    static func serving(_ quantity: Double, unit: ServingUnit) -> String {
        serving(quantity, unitName: unit.displayName(quantity: quantity))
    }

    /// 只有单位名字（记录里存的）时
    static func serving(_ quantity: Double, unitName: String) -> String {
        if quantity == 0.5 {
            return AppLanguage.current == .zh ? "半\(unitName)" : "½ \(unitName)"
        }
        return "\(number(quantity)) \(unitName)"
    }

    /// 「约 150 克」「250 毫升」：自然份量换算出来的是估算，前面写「约」
    static func amount(_ amount: Double, unit: AmountUnit, approximate: Bool) -> String {
        let n = amount >= 10 ? amount.noDecimal : amount.oneDecimal
        switch (unit, approximate) {
        case (.gram, true): return String(localized: "约 \(n) 克")
        case (.gram, false): return String(localized: "\(n) 克")
        case (.milliliter, true): return String(localized: "约 \(n) 毫升")
        case (.milliliter, false): return String(localized: "\(n) 毫升")
        }
    }

    /// 热量：「174 千卡」，估算的写「约 350 千卡」
    static func kcal(_ kcal: Double, isEstimate: Bool) -> String {
        isEstimate ? String(localized: "约 \(kcal.noDecimal) 千卡") : String(localized: "\(kcal.noDecimal) 千卡")
    }

    /// 每 100 克（毫升）多少千卡：「116 千卡 / 100 克」，估算的「约 180 千卡 / 100 克」
    static func per100(_ kcal: Double, unit: AmountUnit, isEstimate: Bool) -> String {
        let n = isEstimate ? ((kcal / 10).rounded() * 10).noDecimal : kcal.noDecimal
        switch (unit, isEstimate) {
        case (.gram, false): return String(localized: "\(n) 千卡 / 100 克")
        case (.gram, true): return String(localized: "约 \(n) 千卡 / 100 克")
        case (.milliliter, false): return String(localized: "\(n) 千卡 / 100 毫升")
        case (.milliliter, true): return String(localized: "约 \(n) 千卡 / 100 毫升")
        }
    }

    /// 一种食物的常用份量：「1 碗 · 约 150 克」；不知道重量的「1 份」
    static func commonServing(_ unit: ServingUnit, quantity: Double, amountUnit: AmountUnit?) -> String {
        let serving = serving(quantity, unit: unit)
        guard let amountUnit, unit.amount > 0 else { return serving }
        return "\(serving) · \(amount(quantity * unit.amount, unit: amountUnit, approximate: true))"
    }
}

// MARK: - 从各种来源变成 FoodChoice

nonisolated extension FoodChoice {
    /// 食物库里的一种食物。recent：上次吃这种食物的记录。
    /// 吃过的按上次记的来（「最近吃过」就是想再记一次一样的）：上次的份量；上次的数字（可能是拍照识别的、自己改过的），
    /// 食物库只提供「碗、个」这些单位。上次没有重量（只记了热量）就按上次那一份算
    static func catalog(_ food: CatalogFood, recent: RecentFood? = nil) -> FoodChoice {
        guard let recent else {
            return FoodChoice(
                id: food.ref, name: food.displayName, origin: .catalog(food.id),
                basis: .per100(food.values100, food.baseUnit), units: food.units,
                initialSelection: .natural(unitID: food.units.first?.id ?? "", quantity: food.defaultQuantity),
                isEstimate: food.isEstimate, foodRef: food.ref)
        }
        guard let grams = recent.weightG, grams > 0, let per100 = DietLogMath.per100(recent.values, weightG: grams) else {
            return .recent(recent)
        }
        return FoodChoice(
            id: food.ref, name: recent.name, origin: .catalog(food.id), basis: .per100(per100, recent.amountUnit),
            units: food.units, initialSelection: lastSelection(recent, units: food.units) ?? .amount(grams),
            isEstimate: false, foodRef: food.ref)
    }

    /// 我的食物
    static func custom(_ food: CustomFoodSnapshot, recent: RecentFood? = nil) -> FoodChoice {
        let unit = food.servingUnit
        let basis: NutritionBasis
        if let amount = food.servingAmount, amount > 0, let per100 = DietLogMath.per100(food.servingValues, weightG: amount) {
            basis = .per100(per100, food.amountUnit)
        } else {
            basis = .perServing(food.servingValues)
        }
        return FoodChoice(
            id: FoodRef.custom(food.id), name: food.name, origin: .custom(food.id), basis: basis, units: [unit],
            initialSelection: recent.flatMap { lastSelection($0, units: [unit]) } ?? .natural(unitID: unit.id, quantity: 1),
            isEstimate: food.isAIEstimate, foodRef: FoodRef.custom(food.id))
    }

    /// 最近吃过、但不是来自食物库或我的食物的（以前手动随手记的）：
    /// 知道重量就按「每 100 克」算，上次的量当作「1 份」；不知道重量就按份数乘上次的营养。
    /// catalogUnits：名字和食物库里的某种食物一样时，借用它的自然单位（「米饭」也能选碗）
    static func recent(_ food: RecentFood, catalogUnits: [ServingUnit] = []) -> FoodChoice {
        let id = "recent:\(food.id)"
        if let grams = food.weightG, grams > 0, let per100 = DietLogMath.per100(food.values, weightG: grams) {
            let units = catalogUnits.isEmpty ? [ServingUnit.serving(id: "last", amount: grams)] : catalogUnits
            return FoodChoice(
                id: id, name: food.name, origin: .recent, basis: .per100(per100, food.amountUnit), units: units,
                initialSelection: lastSelection(food, units: units) ?? .amount(grams), isEstimate: false, foodRef: nil)
        }
        let unit = ServingUnit.serving(id: "last", amount: 0)
        return FoodChoice(
            id: id, name: food.name, origin: .recent, basis: .perServing(food.values), units: [unit],
            initialSelection: .natural(unitID: unit.id, quantity: 1), isEstimate: false, foodRef: nil)
    }

    /// AI 估算的结果（还没保存到我的食物）
    static func aiEstimate(_ estimate: FoodEstimate) -> FoodChoice {
        let unit = ServingUnit.named(estimate.servingName, id: "ai", amount: estimate.servingAmount)
        return FoodChoice(
            id: "ai:\(estimate.name)", name: estimate.name, origin: .aiEstimate,
            basis: .per100(estimate.per100, estimate.amountUnit), units: [unit],
            initialSelection: .natural(unitID: unit.id, quantity: 1), isEstimate: true, foodRef: nil)
    }

    /// 上次吃的份量：上次选的是哪个自然单位就还是它；上次填的克数正好是某个单位的整数倍就换成那个单位；
    /// 都不是就按上次的克数
    private static func lastSelection(_ food: RecentFood, units: [ServingUnit]) -> ServingSelection? {
        if let unitID = food.servingUnitID, let quantity = food.servingQuantity, units.contains(where: { $0.id == unitID }) {
            return .natural(unitID: unitID, quantity: quantity)
        }
        guard let grams = food.weightG, grams > 0 else { return nil }
        for unit in units {
            if let quantity = ServingMath.quantity(forAmount: grams, unit: unit) {
                return .natural(unitID: unit.id, quantity: quantity)
            }
        }
        return .amount(grams)
    }
}
