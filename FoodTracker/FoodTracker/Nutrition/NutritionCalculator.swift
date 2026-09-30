//
//  NutritionCalculator.swift
//  FoodTracker
//
//  每日热量和三大营养素目标的计算逻辑。
//  这个文件只做「算数」，不涉及界面和存储，所以可以单独写单元测试
//  （测试在 FoodTrackerTests/NutritionCalculatorTests.swift）。
//
//  参数的依据（详细来源见 ExplanationView.swift 底部的参考资料）：
//  - 基础代谢：Mifflin-St Jeor 公式（1990）
//  - 减脂缺口：每天少吃 20%，最多 500 千卡（ACSM 建议 250～500 千卡；超过 500 会影响肌肉），
//    并且不超过体重每周下降约 0.7% 的速度，BMI 低于 22 时按 0.5%（ISSN：越瘦减得越慢）
//  - 增肌盈余：每天多吃 10%，最多 500 千卡（Iraki 等，2019：新手 10～20%）；体重偏轻时至少 300 千卡（NHS）
//  - 蛋白质：每公斤 1.6～2.0 克，在 ISSN（1.4～2.0）和 ACSM（1.2～2.0）的范围内
//  - 脂肪：占热量 25%，不低于 20%（ACSM、美国国家科学院）
//  - 碳水：不低于 130 克/天（美国国家科学院推荐量）
//  - 热量下限：女性 1200、男性 1500 千卡（Harvard Health）
//  - 不提供减脂的情况：BMI 低于 18.5（WHO 偏轻）；65 岁以上且 BMI 低于 30（ESPEN 老年营养指南）
//  - BMI 低于 16（WHO 重度消瘦）：目标照常算，但建议请医生或注册营养师来定，目标当作「至少吃到的量」
//
//  类型前面的 nonisolated 表示：这些纯计算代码不需要限定在主线程运行，
//  在任何地方（包括单元测试）都可以直接调用。
//

import Foundation

// MARK: - 用户可以选的选项

/// 生理性别：基础代谢公式里，男性和女性的常数不同
nonisolated enum Sex: String, CaseIterable, Codable {
    case male, female

    var title: String {
        switch self {
        case .male: String(localized: "男")
        case .female: String(localized: "女")
        }
    }
}

/// 日常活动量
nonisolated enum ActivityLevel: String, CaseIterable, Codable {
    case sedentary, light, moderate, active, veryActive

    /// 活动系数：基础代谢 × 活动系数 = 每日总消耗
    var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    var title: String {
        switch self {
        case .sedentary: String(localized: "久坐")
        case .light: String(localized: "轻度活动")
        case .moderate: String(localized: "中度活动")
        case .active: String(localized: "高度活动")
        case .veryActive: String(localized: "非常高")
        }
    }

    /// 通俗的说明，帮用户选对档位
    var detail: String {
        switch self {
        case .sedentary: String(localized: "办公室工作，平时基本不运动")
        case .light: String(localized: "每周运动 1～3 次")
        case .moderate: String(localized: "每周运动 3～5 次")
        case .active: String(localized: "每周运动 6～7 次，或需要长时间站立走动的工作")
        case .veryActive: String(localized: "体力劳动，或每天训练两次")
        }
    }
}

/// 目标
nonisolated enum Goal: String, CaseIterable, Codable {
    case loseFat, maintain, gainMuscle

    /// 热量调整比例：减脂少吃 20%，增肌多吃 10%（还有每日上限，见 NutritionCalculator）
    var calorieAdjustmentShare: Double {
        switch self {
        case .loseFat: -0.20
        case .maintain: 0
        case .gainMuscle: 0.10
        }
    }

    /// 每公斤体重每天吃多少克蛋白质
    var proteinPerKg: Double {
        switch self {
        case .loseFat: 2.0  // 减脂时多吃一些蛋白质，帮助保住肌肉
        case .maintain: 1.6
        case .gainMuscle: 1.8
        }
    }

    var title: String {
        switch self {
        case .loseFat: String(localized: "减脂")
        case .maintain: String(localized: "维持")
        case .gainMuscle: String(localized: "增肌")
        }
    }

    var detail: String {
        switch self {
        case .loseFat: String(localized: "适度少吃，慢慢减掉脂肪，同时保住肌肉")
        case .maintain: String(localized: "保持现在的体重")
        case .gainMuscle: String(localized: "适度多吃，配合力量训练增加肌肉")
        }
    }
}

// MARK: - 输入和结果

/// 计算需要的全部信息
nonisolated struct BodyInfo: Equatable {
    var sex: Sex
    var age: Int  // 岁
    var heightCm: Double  // 厘米
    var weightKg: Double  // 公斤
    var activity: ActivityLevel
    var goal: Goal

    var bmi: Double { NutritionCalculator.bmi(heightCm: heightCm, weightKg: weightKg) }
}

/// 计算结果。热量单位是千卡，营养素单位是克。
nonisolated struct DailyTargets: Equatable {
    let bmr: Double  // 基础代谢：躺着不动一天也要消耗的热量
    let tdee: Double  // 每日总消耗：基础代谢 × 活动系数
    let adjustment: Double  // 按目标调整的热量：减脂是负数，增肌是正数，维持是 0
    let maxAdjustment: Double  // 这个人每天最多调整多少热量（减脂时和体重有关）
    let goalCalories: Double  // 调整后的热量（还没套用安全下限）
    let calorieFloor: Double  // 安全下限
    let calories: Double  // 最终的每日热量目标
    let proteinReferenceWeightKg: Double  // 算蛋白质用的体重（超重时按 BMI 25 对应的体重）
    let proteinG: Double
    let fatG: Double
    let carbsG: Double

    /// 是否因为安全下限，把热量调高了
    var isRaisedToFloor: Bool { calories > goalCalories }

    /// 蛋白质是否因为「不超过总热量 35%」被压低了
    var isProteinCapped: Bool {
        proteinG * NutritionCalculator.kcalPerGramProtein >= calories * NutritionCalculator.maxProteinShare - 0.001
    }

    /// 脂肪实际占总热量的比例（通常是 25%，为了保住碳水可能降到 20%）
    var fatShare: Double { fatG * NutritionCalculator.kcalPerGramFat / calories }
}

// MARK: - 计算

nonisolated enum NutritionCalculator {
    /// 减脂或增肌时，每天最多调整多少热量
    static let maxDailyAdjustment = 500.0
    /// 减脂缺口还不能超过「每公斤体重 7.7 千卡」（约每周减 0.7% 体重）；偏瘦的人（BMI 低于 22）按 5.5（约 0.5%）
    static let maxDeficitPerKg = 7.7
    static let leanMaxDeficitPerKg = 5.5
    static let leanBMI = 22.0
    /// 体重偏轻的人增肌时，每天至少多吃这么多
    static let minSurplusWhenUnderweight = 300.0
    /// 脂肪占每日热量的目标比例，以及不能再低的比例
    static let fatShare = 0.25
    static let minFatShare = 0.20
    /// 蛋白质最多占每日热量的比例
    static let maxProteinShare = 0.35
    /// 碳水每天至少这么多克
    static let minCarbsG = 130.0
    /// 算蛋白质时，体重最多按这个 BMI 对应的体重来算
    static let proteinReferenceBMI = 25.0

    /// 每克营养素提供的热量（千卡）
    static let kcalPerGramProtein = 4.0
    static let kcalPerGramCarbs = 4.0
    static let kcalPerGramFat = 9.0

    /// 不在专业人士指导下，每日热量不建议低于这个值
    static func minimumCalories(for sex: Sex) -> Double {
        switch sex {
        case .male: 1500
        case .female: 1200
        }
    }

    /// 基础代谢（Mifflin-St Jeor 公式）
    /// 男性：10 × 体重 + 6.25 × 身高 − 5 × 年龄 + 5
    /// 女性：10 × 体重 + 6.25 × 身高 − 5 × 年龄 − 161
    static func bmr(sex: Sex, age: Int, heightCm: Double, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        }
    }

    /// 身体质量指数 BMI = 体重（公斤）÷ 身高（米）的平方
    static func bmi(heightCm: Double, weightKg: Double) -> Double {
        let heightM = heightCm / 100
        return weightKg / (heightM * heightM)
    }

    /// 算蛋白质用的体重：超重的人按 BMI 25 对应的体重算，避免蛋白质目标高得吃不下
    static func proteinReferenceWeight(heightCm: Double, weightKg: Double) -> Double {
        let heightM = heightCm / 100
        return min(weightKg, proteinReferenceBMI * heightM * heightM)
    }

    /// 减脂时每天最多少吃多少：不超过 500 千卡，也不超过按体重换算的量
    static func maxDeficit(for body: BodyInfo) -> Double {
        let perKg = body.bmi < leanBMI ? leanMaxDeficitPerKg : maxDeficitPerKg
        return min(maxDailyAdjustment, perKg * body.weightKg)
    }

    /// 算出每日热量和三大营养素目标
    static func targets(for body: BodyInfo) -> DailyTargets {
        // 1. 基础代谢
        let bmr = bmr(sex: body.sex, age: body.age, heightCm: body.heightCm, weightKg: body.weightKg)
        // 2. 每日总消耗 = 基础代谢 × 活动系数
        let tdee = bmr * body.activity.factor
        // 3. 按目标调整
        let share = abs(body.goal.calorieAdjustmentShare)
        let maxAdjustment: Double
        let adjustment: Double
        switch body.goal {
        case .maintain:
            maxAdjustment = 0
            adjustment = 0
        case .loseFat:
            // 少吃 20%，但不超过这个人的每日上限
            maxAdjustment = maxDeficit(for: body)
            adjustment = -min(share * tdee, maxAdjustment)
        case .gainMuscle:
            // 多吃 10%，最多 500 千卡；体重偏轻的人至少多吃 300 千卡
            maxAdjustment = maxDailyAdjustment
            let surplus = body.bmi < ProfileValidator.underweightBMI ? max(share * tdee, minSurplusWhenUnderweight) : share * tdee
            adjustment = min(surplus, maxAdjustment)
        }
        let goalCalories = tdee + adjustment
        // 4. 安全下限：不低于公认的最低热量
        let floor = minimumCalories(for: body.sex)
        let calories = max(goalCalories, floor)
        // 5. 蛋白质：按参考体重算，并且不超过总热量的 35%
        let referenceWeight = proteinReferenceWeight(heightCm: body.heightCm, weightKg: body.weightKg)
        let protein = min(
            referenceWeight * body.goal.proteinPerKg,
            calories * maxProteinShare / kcalPerGramProtein
        )
        let proteinCalories = protein * kcalPerGramProtein
        // 6. 脂肪：先按 25% 算；如果这样碳水会不够 130 克，就把脂肪往下调，但不低于 20%
        var fatCalories = calories * fatShare
        let carbsCaloriesAt25 = calories - proteinCalories - fatCalories
        if carbsCaloriesAt25 < minCarbsG * kcalPerGramCarbs {
            fatCalories = max(calories * minFatShare, calories - proteinCalories - minCarbsG * kcalPerGramCarbs)
        }
        let fat = fatCalories / kcalPerGramFat
        // 7. 碳水：剩下的热量都给碳水
        let carbs = (calories - proteinCalories - fatCalories) / kcalPerGramCarbs

        return DailyTargets(
            bmr: bmr,
            tdee: tdee,
            adjustment: adjustment,
            maxAdjustment: maxAdjustment,
            goalCalories: goalCalories,
            calorieFloor: floor,
            calories: calories,
            proteinReferenceWeightKg: referenceWeight,
            proteinG: protein,
            fatG: fat,
            carbsG: carbs
        )
    }
}

// MARK: - 输入检查和安全提示

/// 检查用户填的数字是否合理，以及哪些目标不适合这个人。
/// 返回 nil 表示没问题；否则返回一句给用户看的说明。
nonisolated enum ProfileValidator {
    static let ageRange = 18...80  // 计算公式来自对成年人的研究
    static let heightRange = 120.0...230.0  // 厘米
    static let weightRange = 30.0...250.0  // 公斤
    /// BMI 低于这个值属于体重过轻（世界卫生组织标准）
    static let underweightBMI = 18.5
    /// BMI 低于这个值属于重度消瘦（世界卫生组织标准）：公式算的目标只作参考，建议请医生或营养师来定
    static let severeThinnessBMI = 16.0
    /// BMI 达到这个值属于肥胖（世界卫生组织标准）
    static let obesityBMI = 30.0
    /// 这个年龄以上，减脂要更谨慎（欧洲临床营养学会老年营养指南以 65 岁为界）
    static let seniorAge = 65
    /// 这个年龄以上，提醒蛋白质和肾功能的关系
    static let kidneyNoteAge = 60
    /// BMI 达到这个值时，提醒确认体重单位（可能把「斤」当成了「公斤」）
    static let unitCheckBMI = 40.0
    /// BMI 超出这个范围，数字很可能填错了
    static let plausibleBMIRange = 12.0...60.0

    static func ageError(_ age: Int?) -> String? {
        guard let age else { return String(localized: "请输入年龄（整数）") }
        guard ageRange.contains(age) else {
            return String(localized: "年龄需要在 \(ageRange.lowerBound)～\(ageRange.upperBound) 岁之间，计算公式适用于成年人")
        }
        return nil
    }

    static func heightError(_ heightCm: Double?) -> String? {
        guard let heightCm else { return String(localized: "请输入身高（厘米）") }
        guard heightRange.contains(heightCm) else {
            return String(localized: "身高需要在 \(Int(heightRange.lowerBound))～\(Int(heightRange.upperBound)) 厘米之间")
        }
        return nil
    }

    static func weightError(_ weightKg: Double?) -> String? {
        guard let weightKg else { return String(localized: "请输入体重（公斤）") }
        guard weightRange.contains(weightKg) else {
            return String(localized: "体重需要在 \(Int(weightRange.lowerBound))～\(Int(weightRange.upperBound)) 公斤之间")
        }
        return nil
    }

    /// 身高和体重的组合是否离谱（比如把「斤」当成了「公斤」）。有问题时不允许继续
    static func plausibilityError(heightCm: Double, weightKg: Double) -> String? {
        let bmi = NutritionCalculator.bmi(heightCm: heightCm, weightKg: weightKg)
        guard plausibleBMIRange.contains(bmi) else {
            return String(localized: "身高和体重的组合不太合理（BMI 约 \(bmi.formatted(.number.precision(.fractionLength(0))))），请检查数字和单位：体重单位是公斤，1 公斤 = 2 斤")
        }
        return nil
    }

    /// BMI 很高或很低时，温和地提醒核对数字和单位（不阻止继续）
    static func unitWarning(heightCm: Double, weightKg: Double) -> String? {
        let bmi = NutritionCalculator.bmi(heightCm: heightCm, weightKg: weightKg)
        // 超出合理范围时，体重那一行已经有更明确的错误提示，这里不重复
        guard plausibleBMIRange.contains(bmi) else { return nil }
        // 很高：多半是把「斤」当成了「公斤」
        if bmi >= unitCheckBMI { return String(localized: "请确认体重单位是公斤（1 公斤 = 2 斤）") }
        // 很低：可能是身高或体重打错了一位数字（比如 54 打成 45）
        if bmi < severeThinnessBMI { return String(localized: "请确认身高和体重填写正确（身高单位是厘米，体重单位是公斤）") }
        return nil
    }

    /// 体重是否已经偏轻（BMI 低于 18.5）
    static func isUnderweight(heightCm: Double, weightKg: Double) -> Bool {
        NutritionCalculator.bmi(heightCm: heightCm, weightKg: weightKg) < underweightBMI
    }

    /// 什么情况下不提供「减脂」。返回 nil 表示可以选；否则返回给用户看的说明
    static func fatLossRestriction(age: Int, heightCm: Double, weightKg: Double) -> String? {
        let bmi = NutritionCalculator.bmi(heightCm: heightCm, weightKg: weightKg)
        if bmi < underweightBMI {
            return String(localized: "你的 BMI 约为 \(bmi.formatted(.number.precision(.fractionLength(1))))，低于 \(underweightBMI.formatted())，属于偏轻范围，所以这里不提供减脂目标。可以选择「维持」或「增肌」；如果对体重有顾虑，建议咨询医生或营养师。")
        }
        if age >= seniorAge && bmi < obesityBMI {
            return String(localized: "\(seniorAge) 岁以上、BMI 低于 \(Int(obesityBMI)) 时，不建议主动减重，因为容易连肌肉一起掉。建议选择「维持」并配合力量训练；如果有体重相关的健康问题，请咨询医生。")
        }
        return nil
    }

    /// 针对这个人和这个目标的温和提示（不阻止继续），可能有多条
    static func goalNotes(for body: BodyInfo) -> [String] {
        var notes: [String] = []
        let bmi = body.bmi
        if bmi < severeThinnessBMI {
            // 重度消瘦：不让用户自己加减热量，而是平静地建议找专业的人；不用「危险」「警告」这类吓人的词
            notes.append(String(localized: "BMI 低于 \(Int(severeThinnessBMI)) 时，公式算出的目标不一定适合你，建议请医生或注册营养师帮你确定每天吃多少。在那之前，可以把每日目标当作每天至少要吃到的量。如果吃饭或体重让你感到有压力，也可以找心理咨询师聊聊。"))
        } else if bmi < underweightBMI && body.goal != .loseFat {
            notes.append(String(localized: "体重偏轻时，公式估算的消耗可能偏低。如果两周的平均体重还在下降，每天多吃 200～300 千卡，或咨询医生、营养师。"))
        }
        if body.age >= seniorAge && body.goal == .loseFat {
            notes.append(String(localized: "\(seniorAge) 岁以上减脂要格外注意保住肌肉：配合力量训练，开始前先和医生确认。"))
        }
        if bmi >= obesityBMI && body.goal == .gainMuscle {
            notes.append(String(localized: "体重基数较大时，配合力量训练、按维持热量吃也能长肌肉，同时不额外增加体脂。可以考虑选择「维持」。"))
        }
        if body.age >= kidneyNoteAge {
            notes.append(String(localized: "\(kidneyNoteAge) 岁以上、有高血压或糖尿病，或近一年没查过肾功能的话，按这个蛋白质目标吃之前先问问医生。"))
        }
        return notes
    }
}
