//
//  NutritionCalculatorTests.swift
//  FoodTrackerTests
//
//  用几组示例数据检查计算结果是否正确。
//  运行方法：在 Xcode 里按 ⌘U（Command + U）。
//  每组数据的预期结果都在注释里手算了一遍，方便对照。
//

import Testing

@testable import FoodTracker

/// 小数运算会有极小的误差，所以比较「差不多相等」
private func isClose(_ a: Double, _ b: Double, tolerance: Double = 0.01) -> Bool {
    abs(a - b) <= tolerance
}

@Suite("每日目标计算")
struct NutritionCalculatorTests {

    // 例 1：男，30 岁，180 厘米，80 公斤，中度活动，维持
    // 基础代谢 = 10×80 + 6.25×180 − 5×30 + 5 = 1780
    // 每日总消耗 = 1780 × 1.55 = 2759
    // 维持体重：热量 = 2759
    // 蛋白质参考体重 = min(80, 25×1.8²=81) = 80 → 80 × 1.6 = 128 克（512 千卡，占 18.6%，没超过 35%）
    // 脂肪 = 2759 × 25% ÷ 9 = 76.64 克
    // 碳水 = (2759 − 512 − 2759×25%) ÷ 4 = 389.31 克
    @Test("男性、维持体重")
    func maleMaintain() {
        let body = BodyInfo(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, goal: .maintain)
        let t = NutritionCalculator.targets(for: body)
        #expect(isClose(t.bmr, 1780))
        #expect(isClose(t.tdee, 2759))
        #expect(isClose(t.adjustment, 0))
        #expect(isClose(t.calories, 2759))
        #expect(isClose(t.proteinReferenceWeightKg, 80))
        #expect(isClose(t.proteinG, 128))
        #expect(isClose(t.fatG, 76.64))
        #expect(isClose(t.carbsG, 389.31))
        #expect(!t.isRaisedToFloor)
        #expect(!t.isProteinCapped)
        #expect(isClose(t.fatShare, 0.25, tolerance: 0.0001))
        #expect(isClose(t.expectedWeeklyChangeKg, 0))
    }

    // 例 2：女，28 岁，165 厘米，60 公斤，轻度活动，减脂
    // 基础代谢 = 10×60 + 6.25×165 − 5×28 − 161 = 1330.25
    // 每日总消耗 = 1330.25 × 1.375 = 1829.09
    // 减脂：少吃 20% = 365.82 千卡（没超过 500）→ 1463.28（高于下限 1200）
    // 蛋白质参考体重 = min(60, 25×1.65²=68.06) = 60 → 120 克（480 千卡，占 32.8%）
    // 脂肪 = 1463.28 × 25% ÷ 9 = 40.65 克
    // 碳水 = (1463.28 − 480 − 365.82) ÷ 4 = 154.36 克（≥ 130，脂肪不用调）
    // 预计每周变化 = −365.82 × 7 ÷ 7700 = −0.33 公斤
    @Test("女性、减脂，没有碰到下限")
    func femaleLoseFat() {
        let body = BodyInfo(sex: .female, age: 28, heightCm: 165, weightKg: 60, activity: .light, goal: .loseFat)
        let t = NutritionCalculator.targets(for: body)
        #expect(isClose(t.bmr, 1330.25))
        #expect(isClose(t.tdee, 1829.09))
        #expect(isClose(t.adjustment, -365.82))
        #expect(isClose(t.calories, 1463.28))
        #expect(isClose(t.proteinG, 120))
        #expect(isClose(t.fatG, 40.65))
        #expect(isClose(t.carbsG, 154.36))
        #expect(!t.isRaisedToFloor)
        #expect(isClose(t.expectedWeeklyChangeKg, -0.33))
    }

    // 例 3：女，50 岁，155 厘米，50 公斤，久坐，减脂 → 碰到 1200 千卡的下限，脂肪下调保住碳水
    // 基础代谢 = 10×50 + 6.25×155 − 5×50 − 161 = 1057.75
    // 每日总消耗 = 1057.75 × 1.2 = 1269.3
    // 减脂：少吃 253.86 → 1015.44，低于女性最低 1200 → 调到 1200
    // 蛋白质 = 50 × 2.0 = 100 克（400 千卡，占 33.3%，没超过 35%）
    // 脂肪按 25% 是 300 千卡，那样碳水只有 (1200−400−300)÷4 = 125 克 < 130
    //   → 脂肪降到 1200 − 400 − 130×4 = 280 千卡（占 23.3%，仍高于 20%）= 31.11 克
    // 碳水 = 130 克
    @Test("女性、减脂，热量被调到 1200 千卡下限，脂肪下调保住碳水")
    func femaleFloor() {
        let body = BodyInfo(sex: .female, age: 50, heightCm: 155, weightKg: 50, activity: .sedentary, goal: .loseFat)
        let t = NutritionCalculator.targets(for: body)
        #expect(isClose(t.goalCalories, 1015.44))
        #expect(isClose(t.calorieFloor, 1200))
        #expect(isClose(t.calories, 1200))
        #expect(t.isRaisedToFloor)
        #expect(isClose(t.proteinG, 100))
        #expect(isClose(t.fatG, 31.11))
        #expect(isClose(t.fatShare, 0.2333, tolerance: 0.001))
        #expect(isClose(t.carbsG, 130))
    }

    // 例 4：女，45 岁，155 厘米，58 公斤，久坐，减脂 → 蛋白质被 35% 上限压低
    // 基础代谢 = 580 + 968.75 − 225 − 161 = 1162.75；总消耗 = 1395.3；减脂 1116.24 → 调到 1200
    // 蛋白质按 58 × 2.0 = 116 克（464 千卡，占 38.7%）→ 压到 1200 × 35% ÷ 4 = 105 克（420 千卡）
    // 脂肪按 25% 时碳水 = (1200−420−300)÷4 = 120 < 130 → 脂肪降到 1200−420−520 = 260 千卡 = 28.89 克
    // 碳水 = 130 克
    @Test("蛋白质不超过总热量的 35%")
    func proteinCap() {
        let body = BodyInfo(sex: .female, age: 45, heightCm: 155, weightKg: 58, activity: .sedentary, goal: .loseFat)
        let t = NutritionCalculator.targets(for: body)
        #expect(isClose(t.calories, 1200))
        #expect(isClose(t.proteinG, 105))
        #expect(t.isProteinCapped)
        #expect(isClose(t.fatG, 28.89))
        #expect(isClose(t.carbsG, 130))
    }

    // 例 5：男，25 岁，180 厘米，100 公斤（BMI 30.9），久坐，减脂 → 蛋白质按 BMI 25 的体重算
    // 基础代谢 = 1000 + 1125 − 125 + 5 = 2005；总消耗 = 2406；减脂少吃 20% = 481.2 → 1924.8
    // 蛋白质参考体重 = 25 × 1.8² = 81 公斤 → 81 × 2.0 = 162 克（648 千卡，占 33.7%）
    // 脂肪 = 1924.8 × 25% ÷ 9 = 53.47 克
    // 碳水 = (1924.8 − 648 − 481.2) ÷ 4 = 198.9 克
    @Test("超重时蛋白质按 BMI 25 对应的体重计算")
    func proteinReferenceWeight() {
        let body = BodyInfo(sex: .male, age: 25, heightCm: 180, weightKg: 100, activity: .sedentary, goal: .loseFat)
        let t = NutritionCalculator.targets(for: body)
        #expect(isClose(t.bmr, 2005))
        #expect(isClose(t.calories, 1924.8))
        #expect(!t.isRaisedToFloor)
        #expect(isClose(t.proteinReferenceWeightKg, 81))
        #expect(isClose(t.proteinG, 162))
        #expect(isClose(t.fatG, 53.47))
        #expect(isClose(t.carbsG, 198.9))
    }

    // 例 6：男，30 岁，185 厘米，90 公斤，非常高活动量，减脂 → 缺口被 500 千卡上限限制
    // 基础代谢 = 900 + 1156.25 − 150 + 5 = 1911.25；总消耗 = 1911.25 × 1.9 = 3631.38
    // 20% 是 726.28 千卡，超过 500 → 只少吃 500 → 3131.38
    @Test("减脂每天最多少吃 500 千卡")
    func deficitCap() {
        let body = BodyInfo(sex: .male, age: 30, heightCm: 185, weightKg: 90, activity: .veryActive, goal: .loseFat)
        let t = NutritionCalculator.targets(for: body)
        #expect(isClose(t.tdee, 3631.38))
        #expect(isClose(t.adjustment, -500))
        #expect(isClose(t.calories, 3131.38))
        #expect(isClose(t.expectedWeeklyChangeKg, -0.45))
    }

    // 例 7：男，22 岁，175 厘米，65 公斤，高度活动，增肌
    // 基础代谢 = 10×65 + 6.25×175 − 5×22 + 5 = 1638.75
    // 每日总消耗 = 1638.75 × 1.725 = 2826.84
    // 增肌：多吃 10% = 282.68（没超过 500）→ 3109.53
    // 蛋白质参考体重 = min(65, 25×1.75²=76.56) = 65 → 65 × 1.8 = 117 克
    // 脂肪 = 3109.53 × 25% ÷ 9 = 86.38 克
    // 碳水 = (3109.53 − 117×4 − 3109.53×25%) ÷ 4 = 466.04 克
    @Test("男性、增肌")
    func maleGainMuscle() {
        let body = BodyInfo(sex: .male, age: 22, heightCm: 175, weightKg: 65, activity: .active, goal: .gainMuscle)
        let t = NutritionCalculator.targets(for: body)
        #expect(isClose(t.bmr, 1638.75))
        #expect(isClose(t.tdee, 2826.84))
        #expect(isClose(t.adjustment, 282.68))
        #expect(isClose(t.calories, 3109.53))
        #expect(isClose(t.proteinG, 117))
        #expect(isClose(t.fatG, 86.38))
        #expect(isClose(t.carbsG, 466.04))
        #expect(isClose(t.expectedWeeklyChangeKg, 0.26))
    }

    // 对各种组合做通用检查：热量不低于下限、调整不超过 500、蛋白质不超过 35%、
    // 脂肪在 20%～25% 之间、碳水不少于 130 克，并且三大营养素的热量加起来等于每日热量
    @Test("所有组合：下限、上限和加总都成立")
    func invariantsForAllCombinations() {
        let bodies: [(Double, Double, Int)] = [
            (120, 30, 18), (150, 45, 18), (155, 58, 45), (165, 60, 35), (180, 80, 50), (180, 120, 40), (230, 250, 80),
        ]
        for sex in Sex.allCases {
            for activity in ActivityLevel.allCases {
                for goal in Goal.allCases {
                    for (height, weight, age) in bodies {
                        let body = BodyInfo(
                            sex: sex, age: age, heightCm: height, weightKg: weight, activity: activity, goal: goal)
                        let t = NutritionCalculator.targets(for: body)
                        #expect(t.calories >= NutritionCalculator.minimumCalories(for: sex))
                        #expect(abs(t.adjustment) <= NutritionCalculator.maxDailyAdjustment + 0.001)
                        #expect(t.proteinG > 0)
                        #expect(t.proteinG * 4 <= t.calories * NutritionCalculator.maxProteinShare + 0.001)
                        #expect(t.fatShare >= NutritionCalculator.minFatShare - 0.0001)
                        #expect(t.fatShare <= NutritionCalculator.fatShare + 0.0001)
                        #expect(t.carbsG >= NutritionCalculator.minCarbsG - 0.001)
                        let sum = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9
                        #expect(isClose(sum, t.calories, tolerance: 0.001))
                    }
                }
            }
        }
    }

    @Test("BMI 计算")
    func bmi() {
        // 65 ÷ 1.7² = 22.49
        #expect(isClose(NutritionCalculator.bmi(heightCm: 170, weightKg: 65), 22.49))
    }
}

@Suite("输入检查")
struct ProfileValidatorTests {

    @Test("年龄范围 18～80 岁")
    func age() {
        #expect(ProfileValidator.ageError(nil) != nil)
        #expect(ProfileValidator.ageError(17) != nil)
        #expect(ProfileValidator.ageError(18) == nil)
        #expect(ProfileValidator.ageError(80) == nil)
        #expect(ProfileValidator.ageError(81) != nil)
    }

    @Test("身高范围 120～230 厘米")
    func height() {
        #expect(ProfileValidator.heightError(nil) != nil)
        #expect(ProfileValidator.heightError(119.9) != nil)
        #expect(ProfileValidator.heightError(120) == nil)
        #expect(ProfileValidator.heightError(230) == nil)
        #expect(ProfileValidator.heightError(230.1) != nil)
    }

    @Test("体重范围 30～250 公斤")
    func weight() {
        #expect(ProfileValidator.weightError(nil) != nil)
        #expect(ProfileValidator.weightError(29.9) != nil)
        #expect(ProfileValidator.weightError(30) == nil)
        #expect(ProfileValidator.weightError(250) == nil)
        #expect(ProfileValidator.weightError(250.5) != nil)
    }

    @Test("体重偏轻的判断和提示")
    func underweight() {
        // 170 厘米、50 公斤：BMI 约 17.3，低于 18.5
        #expect(ProfileValidator.isUnderweight(heightCm: 170, weightKg: 50))
        #expect(ProfileValidator.underweightMessage(heightCm: 170, weightKg: 50) != nil)
        // 170 厘米、60 公斤：BMI 约 20.8，正常
        #expect(!ProfileValidator.isUnderweight(heightCm: 170, weightKg: 60))
        #expect(ProfileValidator.underweightMessage(heightCm: 170, weightKg: 60) == nil)
    }
}
