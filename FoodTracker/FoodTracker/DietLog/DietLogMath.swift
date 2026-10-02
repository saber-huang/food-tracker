//
//  DietLogMath.swift
//  FoodTracker
//
//  饮食记录的计算：合计、按重量换算、四舍五入、和每日目标比较、输入检查。
//  只做计算，不涉及界面和存储，所以可以单独写单元测试（FoodTrackerTests/DietLogMathTests.swift）。
//
//  四舍五入的规则（改之前先看测试）：
//  - 热量取整，蛋白质、碳水、脂肪保留 1 位小数，只在「存进去」和「算合计」时各做一次
//  - Swift 的 rounded() 是「四舍五入」，2.5 → 3；后端 Python 的 round 是「四舍六入五成双」，2.5 → 2。
//    两边偶尔差 1，这是正常的，不要为了让测试通过去改规则
//

import Foundation

// MARK: - 热量和三大营养素

/// 一组热量和三大营养素（一种食物、一餐或一整天）
nonisolated struct NutrientValues: Hashable, Sendable {
    var caloriesKcal = 0.0
    var proteinG = 0.0
    var carbsG = 0.0
    var fatG = 0.0

    static let zero = NutrientValues()

    static func + (a: NutrientValues, b: NutrientValues) -> NutrientValues {
        NutrientValues(
            caloriesKcal: a.caloriesKcal + b.caloriesKcal,
            proteinG: a.proteinG + b.proteinG,
            carbsG: a.carbsG + b.carbsG,
            fatG: a.fatG + b.fatG
        )
    }
}

// 写在扩展里，才能保留自动生成的 NutrientValues(caloriesKcal:proteinG:carbsG:fatG:)
nonisolated extension NutrientValues {
    /// 识别结果里的一种食物
    init(item: FoodItem) {
        self.init(caloriesKcal: item.caloriesKcal, proteinG: item.proteinG, carbsG: item.carbsG, fatG: item.fatG)
    }

    /// 一道食谱（整份）
    init(recipe: Recipe) {
        self.init(caloriesKcal: recipe.caloriesKcal, proteinG: recipe.proteinG, carbsG: recipe.carbsG, fatG: recipe.fatG)
    }
}

// MARK: - 可以修改的一项食物

/// 可以修改的一项食物：识别结果页上的一行，也是编辑表单的输入和输出
nonisolated struct EditableItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var weightG: Double?  // nil = 不知道重量
    var values: NutrientValues
    var confidence: Confidence?  // AI 的把握；nil = 用户改过（显示「已修改」）或手动添加的
    var meal: MealType  // 记到哪一餐
    /// 记到哪一天：20260929 这样的数字（和 FoodEntry.dayKey 一样）。
    /// 从打开表单的那一刻起就用数字，一直带到保存：中途手机换了时区，也还是这一天
    var dayKey: Int
    /// weightG 的单位：克，或者毫升（牛奶、饮料）
    var amountUnit: AmountUnit = .gram
    /// 选了自然份量时（「1.5 碗」）：哪个单位、几份；直接填克数时是 nil
    var serving: ServingChoice? = nil
    /// 来自哪种食物（catalog:rice、custom:<UUID>）；随手填写、拍照识别的是 nil
    var foodRef: String? = nil
    var oilLevel: OilLevel? = nil  // 家常菜选的油量（少油 / 多油；正常是 nil）
}

nonisolated extension EditableItem {
    /// 从识别结果的一种食物开始。AI 给的重量是 0 表示不知道重量
    init(_ item: FoodItem, meal: MealType, dayKey: Int) {
        self.init(
            id: UUID(),
            name: item.name,
            weightG: item.weightG > 0 ? item.weightG : nil,
            values: NutrientValues(item: item),
            confidence: item.confidence,
            meal: meal,
            dayKey: dayKey
        )
    }
}

// MARK: - 和每日目标比较

/// 一天吃了多少、离目标还有多少。热量都是整数，所以不会出现「-0」或「比目标多 0 千卡」
nonisolated struct DayProgress: Equatable {
    let targetKcal: Double  // 目标，取整（和其他页面显示的一样）
    let consumedKcal: Double  // 已记录，取整
    /// 还可以吃多少；负数 = 比目标多了
    var remainingKcal: Double { targetKcal - consumedKcal }
    var isOver: Bool { remainingKcal < 0 }
    // 给进度条用的比例，0～1，超过目标也只画满（用没取整的原值算）
    let kcalFraction: Double
    let proteinFraction: Double
    let carbsFraction: Double
    let fatFraction: Double
}

// MARK: - 计算

nonisolated enum DietLogMath {
    /// 合计：加起来之后再四舍五入，消掉小数运算的误差（比如 3.9 + 24.7 = 28.599999999999998）
    static func total(of values: [NutrientValues]) -> NutrientValues {
        rounded(values.reduce(.zero, +))
    }

    /// 每 100 克含多少热量和营养素（不四舍五入）。不知道重量时是 nil
    static func per100(_ values: NutrientValues, weightG: Double?) -> NutrientValues? {
        guard let weight = weightG, weight > 0 else { return nil }
        return NutrientValues(
            caloriesKcal: values.caloriesKcal / weight * 100,
            proteinG: values.proteinG / weight * 100,
            carbsG: values.carbsG / weight * 100,
            fatG: values.fatG / weight * 100
        )
    }

    /// 按「每 100 克的含量」算出 grams 克的热量和营养素（不四舍五入）
    static func scaled(_ per100: NutrientValues, toWeightG grams: Double) -> NutrientValues {
        NutrientValues(
            caloriesKcal: per100.caloriesKcal * grams / 100,
            proteinG: per100.proteinG * grams / 100,
            carbsG: per100.carbsG * grams / 100,
            fatG: per100.fatG * grams / 100
        )
    }

    /// 热量取整
    static func round0(_ x: Double) -> Double { x.rounded() }

    /// 克数保留 1 位小数
    static func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    static func rounded(_ v: NutrientValues) -> NutrientValues {
        NutrientValues(caloriesKcal: round0(v.caloriesKcal), proteinG: round1(v.proteinG), carbsG: round1(v.carbsG), fatG: round1(v.fatG))
    }

    /// 一道食谱的重量：食材生重加起来，保留 1 位小数；加起来是 0 就当作不知道重量（nil）
    static func weight(of recipe: Recipe) -> Double? {
        let grams = round1(recipe.ingredients.map(\.grams).reduce(0, +))
        return grams > 0 ? grams : nil
    }

    /// 按三大营养素算出来的热量：蛋白质和碳水每克 4 千卡，脂肪每克 9 千卡
    static func macroKcal(_ v: NutrientValues) -> Double {
        v.proteinG * NutritionCalculator.kcalPerGramProtein
            + v.carbsG * NutritionCalculator.kcalPerGramCarbs
            + v.fatG * NutritionCalculator.kcalPerGramFat
    }

    /// value 占 target 的比例，限制在 0～1 之间；目标不大于 0 时是 0
    static func fraction(_ value: Double, of target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(max(value / target, 0), 1)
    }

    /// 一天吃的和每日目标比较
    static func progress(consumed: NutrientValues, targets: DailyTargets) -> DayProgress {
        DayProgress(
            // 和 .noDecimal 的显示方式一样取整（四舍六入五成双），这样首页和「我的」页的目标数字一致
            targetKcal: targets.calories.rounded(.toNearestOrEven),
            consumedKcal: round0(consumed.caloriesKcal),
            kcalFraction: fraction(consumed.caloriesKcal, of: targets.calories),
            proteinFraction: fraction(consumed.proteinG, of: targets.proteinG),
            carbsFraction: fraction(consumed.carbsG, of: targets.carbsG),
            fatFraction: fraction(consumed.fatG, of: targets.fatG)
        )
    }

    /// 按现在几点几分，猜这一顿是哪一餐（记录时默认选中它，用户可以改）。时间段和产品规划一致：
    /// 4:00–10:30 早餐，10:30–14:30 午餐，17:00–21:30 晚餐，其他时间加餐。
    /// 吃完饭过一会儿才记也常见，所以午餐、晚餐的时间段留得宽一些
    static func suggestedMeal(hour: Int, minute: Int = 0) -> MealType {
        switch hour * 60 + minute {
        case (4 * 60)..<(10 * 60 + 30): .breakfast
        case (10 * 60 + 30)..<(14 * 60 + 30): .lunch
        case (17 * 60)..<(21 * 60 + 30): .dinner
        default: .snack
        }
    }

    /// 按某个时刻猜是哪一餐（用手机现在的时区）
    static func suggestedMeal(at date: Date, calendar: Calendar = DayMath.calendar) -> MealType {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return suggestedMeal(hour: time.hour ?? 0, minute: time.minute ?? 0)
    }
}

// MARK: - 输入检查

/// 检查一项食物填得对不对。和 ProfileValidator 一样：返回 nil 表示没问题，否则是给用户看的一句话
nonisolated enum EntryValidator {
    static let nameMaxLength = 40
    static let weightRange = 0.0...5000.0  // 克
    static let caloriesRange = 0.0...5000.0  // 千卡
    static let macroRange = 0.0...1000.0  // 克

    static func nameError(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return String(localized: "请输入食物名称") }
        if trimmed.count > nameMaxLength { return String(localized: "名称最多 \(nameMaxLength) 个字") }
        return nil
    }

    /// 重量可以不填
    static func weightError(text: String) -> String? {
        if NumberText.isBlank(text) { return nil }
        guard let grams = NumberText.number(from: text) else { return String(localized: "请输入数字") }
        return weightRange.contains(grams) ? nil : String(localized: "份量需要在 0～5000 克之间")
    }

    /// 热量必须填
    static func caloriesError(text: String) -> String? {
        if NumberText.isBlank(text) { return String(localized: "请输入热量") }
        guard let kcal = NumberText.number(from: text) else { return String(localized: "请输入数字") }
        return caloriesRange.contains(kcal) ? nil : String(localized: "热量需要在 0～5000 千卡之间")
    }

    /// 三大营养素可以不填（不填按 0 算）；name 是「蛋白质」「碳水」「脂肪」
    static func macroError(text: String, name: String) -> String? {
        if NumberText.isBlank(text) { return nil }
        guard let grams = NumberText.number(from: text) else { return String(localized: "请输入数字") }
        return macroRange.contains(grams) ? nil : String(localized: "\(name)需要在 0～1000 克之间")
    }

    /// 灰色提醒（不阻止保存）：填的热量和按三大营养素算出来的差太多，可能是填错了。
    /// 三种营养素都填了才两头比较；有没填的（算 0）时，按营养素算的热量只会偏少，所以只在「反而更多」时提醒
    static func kcalMismatchWarning(_ v: NutrientValues) -> String? {
        let fromMacros = DietLogMath.macroKcal(v)
        let allFilled = v.proteinG > 0 && v.carbsG > 0 && v.fatG > 0
        let gap = allFilled ? abs(fromMacros - v.caloriesKcal) : fromMacros - v.caloriesKcal
        guard v.caloriesKcal >= 50, gap > 0.3 * v.caloriesKcal else { return nil }
        // 用 NumberText 转文字：特别大的数也不会闪退（直接转成 Int 会）
        return String(localized: "按三大营养素算约 \(NumberText.text(from: DietLogMath.round0(fromMacros))) 千卡，和填写的热量差得比较多，可以再核对一下。")
    }

    /// 灰色提醒（不阻止保存）：三大营养素加起来比食物本身还重，多半是单位填错了
    static func macrosExceedWeightWarning(_ v: NutrientValues, weightG: Double?) -> String? {
        guard let weight = weightG, weight > 0, v.proteinG + v.carbsG + v.fatG > weight * 1.05 + 1 else { return nil }
        return String(localized: "蛋白质、碳水、脂肪加起来超过了份量，请检查单位。")
    }
}
