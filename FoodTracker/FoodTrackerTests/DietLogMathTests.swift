//
//  DietLogMathTests.swift
//  FoodTrackerTests
//
//  饮食记录计算的测试：合计、按重量换算、四舍五入、和目标比较、输入检查。
//  运行方法：在 Xcode 里按 ⌘U。预期结果都手算过（数字来自识别结果页的示例：米饭和宫保鸡丁）。
//

import Foundation
import Testing

@testable import FoodTracker

/// 小数运算会有极小的误差，所以比较「差不多相等」
private func isClose(_ a: Double, _ b: Double, tolerance: Double = 0.01) -> Bool {
    abs(a - b) <= tolerance
}

private func isClose(_ a: NutrientValues, _ b: NutrientValues, tolerance: Double = 1e-9) -> Bool {
    isClose(a.caloriesKcal, b.caloriesKcal, tolerance: tolerance) && isClose(a.proteinG, b.proteinG, tolerance: tolerance)
        && isClose(a.carbsG, b.carbsG, tolerance: tolerance) && isClose(a.fatG, b.fatG, tolerance: tolerance)
}

// 识别结果页的两个示例食物
private let rice = NutrientValues(caloriesKcal: 174, proteinG: 3.9, carbsG: 38.1, fatG: 0.5)  // 米饭 150 克
private let kungPao = NutrientValues(caloriesKcal: 398, proteinG: 24.7, carbsG: 14, fatG: 26.9)  // 宫保鸡丁

/// 测试用的每日目标：只关心热量和三大营养素
private func targets(kcal: Double) -> DailyTargets {
    DailyTargets(
        bmr: 0, tdee: 0, adjustment: 0, maxAdjustment: 0, goalCalories: kcal, calorieFloor: 0, calories: kcal,
        proteinReferenceWeightKg: 0, proteinG: 100, fatG: 50, carbsG: 200)
}

@Suite("饮食记录计算")
struct DietLogMathTests {

    // 174 + 398 = 572；3.9 + 24.7 = 28.6；38.1 + 14 = 52.1；0.5 + 26.9 = 27.4
    @Test("合计")
    func total() {
        #expect(DietLogMath.total(of: [rice, kungPao]) == NutrientValues(caloriesKcal: 572, proteinG: 28.6, carbsG: 52.1, fatG: 27.4))
        #expect(DietLogMath.total(of: []) == .zero)
        #expect(DietLogMath.total(of: [rice]) == DietLogMath.rounded(rice))
    }

    // 米饭 150 克 → 每 100 克：174 ÷ 150 × 100 = 116 千卡，蛋白质 2.6，碳水 25.4，脂肪 0.333…
    @Test("每 100 克的含量")
    func per100() {
        let p = DietLogMath.per100(rice, weightG: 150)
        #expect(p != nil)
        if let p {
            #expect(isClose(p, NutrientValues(caloriesKcal: 116, proteinG: 2.6, carbsG: 25.4, fatG: 1.0 / 3)))
        }
        // 不知道重量时算不出来
        #expect(DietLogMath.per100(rice, weightG: 0) == nil)
        #expect(DietLogMath.per100(rice, weightG: nil) == nil)
        #expect(DietLogMath.per100(rice, weightG: -5) == nil)
    }

    // 米饭改成 200 克：116 × 2 = 232 千卡，蛋白质 5.2，碳水 50.8，脂肪 0.667 → 0.7
    @Test("按重量换算")
    func scaled() throws {
        let p = try #require(DietLogMath.per100(rice, weightG: 150))
        #expect(DietLogMath.rounded(DietLogMath.scaled(p, toWeightG: 200)) == NutrientValues(caloriesKcal: 232, proteinG: 5.2, carbsG: 50.8, fatG: 0.7))
        #expect(DietLogMath.rounded(DietLogMath.scaled(p, toWeightG: 100)) == NutrientValues(caloriesKcal: 116, proteinG: 2.6, carbsG: 25.4, fatG: 0.3))
        #expect(DietLogMath.rounded(DietLogMath.scaled(p, toWeightG: 300)) == NutrientValues(caloriesKcal: 348, proteinG: 7.8, carbsG: 76.2, fatG: 1.0))
        // 75 克：87 千卡，脂肪 0.3（蛋白质和碳水刚好卡在 .x5，这里不比较）
        let half = DietLogMath.rounded(DietLogMath.scaled(p, toWeightG: 75))
        #expect(half.caloriesKcal == 87)
        #expect(half.fatG == 0.3)
    }

    // 按「每 100 克含量」换算回原来的 150 克，数字和最开始完全一样：
    // 中间的小数误差（比如 173.99999999999997）被四舍五入消掉了。
    // 150 → 75 → 150 克来回改的情况在 EntryDraftTests 里测
    @Test("换算回原来的重量，数字不变")
    func roundTrip() throws {
        let p = try #require(DietLogMath.per100(rice, weightG: 150))
        #expect(DietLogMath.rounded(DietLogMath.scaled(p, toWeightG: 150)) == rice)
    }

    // Swift 的 rounded() 遇到 .5 往远离 0 的方向进（2.5 → 3）；后端 Python 的 round 是「五成双」（2.5 → 2）
    @Test("四舍五入的规则")
    func rounding() {
        #expect(DietLogMath.round0(2.5) == 3)
        #expect(DietLogMath.round0(86.5) == 87)
        #expect(DietLogMath.round1(0.25) == 0.3)
        #expect(DietLogMath.round1(28.599999999999998) == 28.6)
        #expect(DietLogMath.round1(0.6667) == 0.7)
        #expect(DietLogMath.round1(0.05) == 0.1)
    }

    // 米饭：3.9×4 + 38.1×4 + 0.5×9 = 172.5；宫保鸡丁：24.7×4 + 14×4 + 26.9×9 = 396.9
    @Test("按三大营养素算热量")
    func macroKcal() {
        #expect(isClose(DietLogMath.macroKcal(rice), 172.5))
        #expect(isClose(DietLogMath.macroKcal(kungPao), 396.9))
        #expect(isClose(DietLogMath.macroKcal(NutrientValues(caloriesKcal: 0, proteinG: 50, carbsG: 50, fatG: 20)), 580))
    }

    // 示例食谱：鸡胸肉 170 + 糙米 45 + 西兰花 150 + 橄榄油 8 = 373 克，590 千卡
    @Test("从食谱记一餐：重量是食材生重合计，营养数据是整份的")
    func recipeMapping() {
        let recipe = Recipe(
            meal: .lunch, name: "清蒸鸡胸肉配西兰花糙米饭",
            ingredients: [
                Ingredient(name: "鸡胸肉", grams: 170), Ingredient(name: "糙米", grams: 45),
                Ingredient(name: "西兰花", grams: 150), Ingredient(name: "橄榄油", grams: 8),
            ],
            steps: [], cookingMinutes: 30, caloriesKcal: 590, proteinG: 48, carbsG: 63, fatG: 16)
        #expect(DietLogMath.weight(of: recipe) == 373)
        #expect(NutrientValues(recipe: recipe) == NutrientValues(caloriesKcal: 590, proteinG: 48, carbsG: 63, fatG: 16))
        // 没有食材克数：当作不知道重量
        let noWeight = Recipe(
            meal: .dinner, name: "x", ingredients: [Ingredient(name: "盐", grams: 0)], steps: [], cookingMinutes: 5,
            caloriesKcal: 10, proteinG: 0, carbsG: 0, fatG: 0)
        #expect(DietLogMath.weight(of: noWeight) == nil)
    }

    @Test("热量和三大营养素对不上时的提醒")
    func kcalMismatch() {
        #expect(EntryValidator.kcalMismatchWarning(rice) == nil)  // 174 和 172.5 很接近
        #expect(EntryValidator.kcalMismatchWarning(NutrientValues(caloriesKcal: 100, proteinG: 50, carbsG: 50, fatG: 20)) != nil)  // 580 ≠ 100
        #expect(EntryValidator.kcalMismatchWarning(NutrientValues(caloriesKcal: 30, proteinG: 0, carbsG: 0, fatG: 10)) == nil)  // 热量太小不提醒
        #expect(EntryValidator.kcalMismatchWarning(NutrientValues(caloriesKcal: 100)) == nil)  // 没填营养素不提醒
        // 只填了一部分营养素：按营养素算的热量只会偏少，不提醒；反而更多才提醒
        #expect(EntryValidator.kcalMismatchWarning(NutrientValues(caloriesKcal: 150, proteinG: 8)) == nil)
        #expect(EntryValidator.kcalMismatchWarning(NutrientValues(caloriesKcal: 100, proteinG: 50)) != nil)  // 200 > 100
        // 特别大的数不会闪退
        #expect(EntryValidator.kcalMismatchWarning(NutrientValues(caloriesKcal: 100, proteinG: 1e20)) != nil)
    }

    @Test("营养素加起来超过重量时的提醒")
    func macrosExceedWeight() {
        #expect(EntryValidator.macrosExceedWeightWarning(NutrientValues(caloriesKcal: 0, proteinG: 60, carbsG: 60, fatG: 10), weightG: 100) != nil)  // 130 > 100
        #expect(EntryValidator.macrosExceedWeightWarning(rice, weightG: 150) == nil)
        #expect(EntryValidator.macrosExceedWeightWarning(rice, weightG: nil) == nil)
        #expect(EntryValidator.macrosExceedWeightWarning(NutrientValues(caloriesKcal: 0, proteinG: 50, carbsG: 50, fatG: 4), weightG: 100) == nil)  // 104 在误差范围内
    }

    @Test("和每日目标比较")
    func progress() {
        let eaten = NutrientValues(caloriesKcal: 572, proteinG: 28.6, carbsG: 52.1, fatG: 27.4)

        // 例 1：男，30 岁，180 厘米，80 公斤，中度活动，维持 → 2759 千卡，蛋白质 128 克
        let t1 = NutritionCalculator.targets(for: BodyInfo(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, goal: .maintain))
        let p = DietLogMath.progress(consumed: eaten, targets: t1)
        #expect(p.targetKcal == 2759)
        #expect(p.consumedKcal == 572)
        #expect(p.remainingKcal == 2187)
        #expect(!p.isOver)
        #expect(isClose(p.kcalFraction, 572.0 / 2759, tolerance: 1e-9))
        #expect(isClose(p.proteinFraction, 28.6 / 128, tolerance: 1e-9))

        // 吃到 3000：比目标多 241，进度条只画满
        let over = DietLogMath.progress(consumed: NutrientValues(caloriesKcal: 3000), targets: t1)
        #expect(over.remainingKcal == -241)
        #expect(over.isOver)
        #expect(over.kcalFraction == 1)

        // 刚好吃到目标：还剩 0，不算超过
        #expect(DietLogMath.progress(consumed: NutrientValues(caloriesKcal: 2759), targets: t1).remainingKcal == 0)
        #expect(!DietLogMath.progress(consumed: NutrientValues(caloriesKcal: 2759.3), targets: t1).isOver)

        // 例 5：目标 1924.8 → 显示 1925；吃了 1925 → 还剩 0，而且不是「-0」
        let t5 = NutritionCalculator.targets(for: BodyInfo(sex: .male, age: 25, heightCm: 180, weightKg: 100, activity: .sedentary, goal: .loseFat))
        let exact = DietLogMath.progress(consumed: NutrientValues(caloriesKcal: 1925), targets: t5)
        #expect(exact.targetKcal == 1925)
        #expect(exact.remainingKcal == 0)
        #expect(exact.remainingKcal.sign == .plus)
        #expect(!exact.isOver)

        // 目标 1269.3 → 1269；吃了 1270 → 多 1
        let a = DietLogMath.progress(consumed: NutrientValues(caloriesKcal: 1270), targets: targets(kcal: 1269.3))
        #expect(a.targetKcal == 1269)
        #expect(a.remainingKcal == -1)
        #expect(a.isOver)

        // 目标 1924.5 → 1924（和其他页面显示的「1,924」一样，五成双）；吃了 1925 → 多 1；吃了 1000 → 还剩 924
        let b = DietLogMath.progress(consumed: NutrientValues(caloriesKcal: 1925), targets: targets(kcal: 1924.5))
        #expect(b.targetKcal == 1924)
        #expect(b.remainingKcal == -1)
        #expect(DietLogMath.progress(consumed: NutrientValues(caloriesKcal: 1000), targets: targets(kcal: 1924.5)).remainingKcal == 924)

        // 目标是 0 时比例是 0，不会除以 0
        let zero = DietLogMath.progress(consumed: eaten, targets: targets(kcal: 0))
        #expect(zero.kcalFraction == 0)
        #expect(zero.kcalFraction.isFinite)
    }

    // 每个时间段的开头和结尾都测一下：4:00–10:30 早餐，10:30–14:30 午餐，17:00–21:30 晚餐，其他时间加餐
    @Test(
        "按时间猜餐次",
        arguments: zip(
            ["03:59", "04:00", "10:29", "10:30", "14:29", "14:30", "16:59", "17:00", "21:29", "21:30", "23:00", "00:00"],
            [MealType.snack, .breakfast, .breakfast, .lunch, .lunch, .snack, .snack, .dinner, .dinner, .snack, .snack, .snack]))
    func suggestedMeal(time: String, expected: MealType) {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        #expect(DietLogMath.suggestedMeal(hour: parts[0], minute: parts[1]) == expected)
    }

    @Test("按某个时刻猜餐次：用传进来的日历算几点")
    func suggestedMealAtDate() {
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let lunchTime = shanghai.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 14, minute: 5))!
        #expect(DietLogMath.suggestedMeal(at: lunchTime, calendar: shanghai) == .lunch)  // 14:05 记午餐，以前会默认成加餐
        let lateDinner = shanghai.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 21, minute: 10))!
        #expect(DietLogMath.suggestedMeal(at: lateDinner, calendar: shanghai) == .dinner)
    }

    // 这些英文会存进手机的数据库，改了就读不出以前的记录，所以用测试固定下来
    @Test("餐次和来源存储用的文字")
    func storedNames() {
        #expect(MealType.allCases.map(\.rawValue) == ["breakfast", "lunch", "dinner", "snack"])
        #expect(MealType.allCases.map(\.title) == ["早餐", "午餐", "晚餐", "加餐"])
        #expect([EntrySource.photo, .manual, .recipe].map(\.rawValue) == ["photo", "manual", "recipe"])
        #expect(MealType(slot: .breakfast) == .breakfast)
        #expect(MealType(slot: .lunch) == .lunch)
        #expect(MealType(slot: .dinner) == .dinner)
    }

    @Test("识别结果的一项变成可修改的一项")
    func editableItem() {
        let item = EditableItem(
            FoodItem(name: "米饭", weightG: 150, caloriesKcal: 174, proteinG: 3.9, carbsG: 38.1, fatG: 0.5, confidence: .high),
            meal: .lunch, dayKey: 20260929)
        #expect(item.weightG == 150)
        #expect(item.values == rice)
        #expect(item.confidence == .high)
        #expect(item.meal == .lunch)
        #expect(item.dayKey == 20260929)
        // AI 给的重量是 0：当作不知道重量
        let noWeight = EditableItem(
            FoodItem(name: "葱花", weightG: 0, caloriesKcal: 2, proteinG: 0.1, carbsG: 0.3, fatG: 0, confidence: .low),
            meal: .lunch, dayKey: 20260929)
        #expect(noWeight.weightG == nil)
    }
}

@Suite("食物条目输入检查")
struct EntryValidatorTests {

    @Test("名称")
    func name() {
        #expect(EntryValidator.nameError("") != nil)
        #expect(EntryValidator.nameError("   ") != nil)
        #expect(EntryValidator.nameError(String(repeating: "米", count: 41)) != nil)
        #expect(EntryValidator.nameError(String(repeating: "米", count: 40)) == nil)  // 正好 40 个字可以
        #expect(EntryValidator.nameError(" 米饭 ") == nil)
    }

    @Test("重量（可以不填）")
    func weight() {
        for text in ["", "0", "150", "62,5", "5000"] {
            #expect(EntryValidator.weightError(text: text) == nil, "\(text) 应该可以")
        }
        for text in ["-5", "5001", "abc"] {
            #expect(EntryValidator.weightError(text: text) != nil, "\(text) 应该报错")
        }
    }

    @Test("热量（必须填）")
    func calories() {
        #expect(EntryValidator.caloriesError(text: "") == "请输入热量")
        for text in ["174", "0", "5000"] {
            #expect(EntryValidator.caloriesError(text: text) == nil, "\(text) 应该可以")
        }
        for text in ["5001", "-1", "abc"] {
            #expect(EntryValidator.caloriesError(text: text) != nil, "\(text) 应该报错")
        }
    }

    @Test("三大营养素（可以不填）")
    func macros() {
        for text in ["", "38.1", "1000"] {
            #expect(EntryValidator.macroError(text: text, name: "碳水") == nil, "\(text) 应该可以")
        }
        #expect(EntryValidator.macroError(text: "1000.1", name: "碳水") == "碳水需要在 0～1000 克之间")
        #expect(EntryValidator.macroError(text: "-0.1", name: "碳水") != nil)
    }

    @Test("文字和数字互相转换")
    func numberText() {
        #expect(NumberText.number(from: " 12,5 ") == 12.5)
        #expect(NumberText.number(from: "abc") == nil)
        #expect(NumberText.number(from: "inf") == nil)
        #expect(NumberText.number(from: "1e400") == nil)
        #expect(NumberText.isBlank("  "))
        #expect(!NumberText.isBlank(" 1 "))
        #expect(NumberText.text(from: 175) == "175")
        #expect(NumberText.text(from: 62.5) == "62.5")
        #expect(NumberText.text(from: 232.0) == "232")
        #expect(NumberText.text(from: 1234) == "1234")  // 没有千位分隔符，放回输入框也能正常识别
        #expect(NumberText.text(from: -0.0) == "0")
        // 特别大的数不会闪退，并且能转回来
        #expect(NumberText.text(from: 2.6e22) == "2.6e+22")
        #expect(NumberText.number(from: NumberText.text(from: 2.6e22)) == 2.6e22)
        #expect(!NumberText.text(from: 1e300).isEmpty)
    }
}
