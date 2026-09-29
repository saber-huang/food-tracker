//
//  ExplanationView.swift
//  FoodTracker
//
//  「怎么算的」说明页：用用户自己的数据，一步步演示每日目标是怎么算出来的。
//  页面上的系数和百分比都直接读取计算模块，改参数时这里会自动跟着变。
//

import SwiftUI

struct ExplanationView: View {
    let bodyInfo: BodyInfo

    private var t: DailyTargets { NutritionCalculator.targets(for: bodyInfo) }

    var body: some View {
        List {
            Section {
                Text("下面用你自己的数据，一步步演示每日目标是怎么算出来的。")
            }

            Section("第 1 步：基础代谢") {
                Text("基础代谢是身体一整天躺着不动，维持心跳、呼吸和体温也要消耗的热量。我们用营养学界常用的 Mifflin-St Jeor 公式估算：")
                FormulaRow(
                    formula: "10 × 体重 \(bodyInfo.weightKg.oneDecimal) + 6.25 × 身高 \(bodyInfo.heightCm.oneDecimal) − 5 × 年龄 \(bodyInfo.age) \(bodyInfo.sex == .male ? "+ 5" : "− 161")",
                    result: "\(t.bmr.noDecimal) 千卡"
                )
                Text("公式最后一项男女不同：男性加 5，女性减 161。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("第 2 步：每日总消耗") {
                Text("再乘上活动系数，得到一天的总消耗。你选的是「\(bodyInfo.activity.title)」（\(bodyInfo.activity.detail)），系数是 \(bodyInfo.activity.factor.threeDecimals)：")
                FormulaRow(
                    formula: "\(t.bmr.noDecimal) × \(bodyInfo.activity.factor.threeDecimals)",
                    result: "\(t.tdee.noDecimal) 千卡"
                )
            }

            Section("第 3 步：按目标调整") {
                Text(goalExplanation)
                FormulaRow(formula: adjustmentFormula, result: "\(t.goalCalories.noDecimal) 千卡")
                if t.isRaisedToFloor {
                    Text("不过这个数低于安全下限。在没有医生或营养师指导时，女性每天不建议低于 \(NutritionCalculator.minimumCalories(for: .female).noDecimal) 千卡、男性不低于 \(NutritionCalculator.minimumCalories(for: .male).noDecimal) 千卡，所以最终目标定为 \(t.calories.noDecimal) 千卡。")
                        .foregroundStyle(.orange)
                }
                if bodyInfo.goal != .maintain {
                    Text(weeklyChangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("第 4 步：三大营养素") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("蛋白质").font(.headline)
                    Text(proteinExplanation)
                    FormulaRow(
                        formula: "\(proteinWeightLabel) × \(bodyInfo.goal.proteinPerKg.oneDecimal)",
                        result: "\(t.proteinG.noDecimal) 克"
                    )
                    if t.isProteinCapped {
                        Text("这个数超过了每日热量的 \(NutritionCalculator.maxProteinShare.percent)，所以按 \(NutritionCalculator.maxProteinShare.percent) 的上限取 \(t.proteinG.noDecimal) 克，给碳水和脂肪留出空间。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("脂肪").font(.headline)
                    Text(fatExplanation)
                    FormulaRow(
                        formula: "\(t.calories.noDecimal) × \(t.fatShare.percent) ÷ 9",
                        result: "\(t.fatG.noDecimal) 克"
                    )
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("碳水").font(.headline)
                    Text("剩下的热量都给碳水，它是训练时最主要的能量来源。蛋白质和碳水每克都约 4 千卡：")
                    FormulaRow(
                        formula: "(\(t.calories.noDecimal) − 蛋白质 \(t.proteinG.noDecimal) × 4 − 脂肪 \(t.fatG.noDecimal) × 9) ÷ 4",
                        result: "\(t.carbsG.noDecimal) 克"
                    )
                }
            }

            Section("要记住的几点") {
                Text("这些数字是根据公式估算的起点，每个人的实际消耗会有差别。")
                Text("可以先按这个目标吃 2～3 周，再根据体重变化小幅调整。")
                Text("本 App 不提供医疗建议。如有疾病、处于孕期或哺乳期，或有饮食失调史，请先咨询医生或注册营养师。")
            }

            Section("参考资料") {
                ForEach(References.all, id: \.url) { reference in
                    Link(reference.title, destination: reference.url)
                }
            }
        }
        .navigationTitle("怎么算的")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 各段说明文字

    private var goalExplanation: String {
        let share = abs(bodyInfo.goal.calorieAdjustmentShare).percent
        let cap = NutritionCalculator.maxDailyAdjustment.noDecimal
        switch bodyInfo.goal {
        case .loseFat:
            return "你的目标是减脂：每天比总消耗少吃 \(share)，但最多少 \(cap) 千卡。缺口不大，体重下降比较平稳，也更容易保住肌肉："
        case .maintain:
            return "你的目标是维持：吃进去的和消耗的差不多就好："
        case .gainMuscle:
            return "你的目标是增肌：每天比总消耗多吃 \(share)，但最多多 \(cap) 千卡，给肌肉生长提供原料，同时不会长太多脂肪："
        }
    }

    private var adjustmentFormula: String {
        switch bodyInfo.goal {
        case .maintain:
            "\(t.tdee.noDecimal) × 1"
        case .loseFat:
            "\(t.tdee.noDecimal) − \(abs(t.adjustment).noDecimal)"
        case .gainMuscle:
            "\(t.tdee.noDecimal) + \(t.adjustment.noDecimal)"
        }
    }

    private var weeklyChangeText: String {
        let change = t.expectedWeeklyChangeKg
        let amount = abs(change).formatted(.number.precision(.fractionLength(1)))
        let direction = change < 0 ? "减少" : "增加"
        return "按 1 公斤脂肪约 7700 千卡粗略估算，体重预计每周\(direction)约 \(amount) 公斤。"
    }

    /// 蛋白质公式里体重那一项怎么写
    private var proteinWeightLabel: String {
        t.proteinReferenceWeightKg < bodyInfo.weightKg
            ? "参考体重 \(t.proteinReferenceWeightKg.oneDecimal)"
            : "体重 \(bodyInfo.weightKg.oneDecimal)"
    }

    private var proteinExplanation: String {
        var text: String =
            switch bodyInfo.goal {
            case .loseFat:
                "减脂时每公斤体重吃 \(bodyInfo.goal.proteinPerKg.oneDecimal) 克蛋白质。多吃一些蛋白质，有助于在少吃的同时保住肌肉。"
            case .maintain:
                "有规律训练的人，蛋白质需求比一般人高一些，按每公斤体重 \(bodyInfo.goal.proteinPerKg.oneDecimal) 克计算。"
            case .gainMuscle:
                "增肌需要充足的蛋白质作为原料，按每公斤体重 \(bodyInfo.goal.proteinPerKg.oneDecimal) 克计算。"
            }
        if t.proteinReferenceWeightKg < bodyInfo.weightKg {
            text += "你的 BMI 超过 \(NutritionCalculator.proteinReferenceBMI.noDecimal)，为了避免目标高得吃不下，按 BMI \(NutritionCalculator.proteinReferenceBMI.noDecimal) 对应的体重 \(t.proteinReferenceWeightKg.oneDecimal) 公斤来算："
        } else {
            text += "："
        }
        return text
    }

    private var fatExplanation: String {
        if t.fatShare < NutritionCalculator.fatShare - 0.0001 {
            return "脂肪一般占每日热量的 \(NutritionCalculator.fatShare.percent)。你的热量目标比较低，为了让碳水不少于 \(NutritionCalculator.minCarbsG.noDecimal) 克，脂肪降到了 \(t.fatShare.percent)（不会低于 \(NutritionCalculator.minFatShare.percent)）。每克脂肪约 9 千卡："
        }
        return "脂肪占每日热量的 \(NutritionCalculator.fatShare.percent)。每克脂肪约 9 千卡："
    }
}

/// 一行算式：左边是算法，右边是结果
private struct FormulaRow: View {
    let formula: String
    let result: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formula)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("= \(result)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
    }
}

/// 说明页底部列出的参考资料
enum References {
    struct Item {
        let title: String
        let url: URL
    }

    static let all: [Item] = [
        Item(
            title: "基础代谢公式：Mifflin 等人，1990 年",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!),
        Item(
            title: "蛋白质建议：国际运动营养学会立场声明，2017 年",
            url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/")!),
        Item(
            title: "减脂速度与饮食安排：国际运动营养学会立场声明，2017 年",
            url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5470183/")!),
        Item(
            title: "增肌期营养建议：Iraki 等人，2019 年",
            url: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC6680710/")!),
        Item(
            title: "运动营养联合声明（热量缺口、脂肪比例）：ACSM 等，2016 年",
            url: URL(string: "https://pubmed.ncbi.nlm.nih.gov/26891166/")!),
        Item(
            title: "碳水、脂肪推荐量：美国国家科学院膳食参考摄入量",
            url: URL(string: "https://www.nationalacademies.org/cdn/materials/9fb9fae1-63a0-4048-88ad-3f972639149a")!),
        Item(
            title: "每日热量下限：Harvard Health",
            url: URL(string: "https://www.health.harvard.edu/staying-healthy/calorie-counting-made-easy")!),
    ]
}

extension Double {
    /// 0.25 → "25%"
    var percent: String { formatted(.percent.precision(.fractionLength(0))) }
    /// 最多 2 位小数：0.8 → "0.8"，1.1 → "1.1"
    var twoDecimals: String { formatted(.number.precision(.fractionLength(0...2))) }
    /// 最多 3 位小数：1.375 → "1.375"
    var threeDecimals: String { formatted(.number.precision(.fractionLength(0...3))) }
}

#Preview("减脂，碰到下限") {
    NavigationStack {
        ExplanationView(
            bodyInfo: BodyInfo(
                sex: .female, age: 45, heightCm: 155, weightKg: 58, activity: .sedentary, goal: .loseFat))
    }
}

#Preview("超重，减脂") {
    NavigationStack {
        ExplanationView(
            bodyInfo: BodyInfo(
                sex: .male, age: 25, heightCm: 180, weightKg: 100, activity: .sedentary, goal: .loseFat))
    }
}
