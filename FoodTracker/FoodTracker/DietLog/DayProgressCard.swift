//
//  DayProgressCard.swift
//  FoodTracker
//
//  「今日」页顶部的卡片：还可以吃多少、已经吃了多少、三大营养素的进度。
//  超过目标时只用灰色写出多了多少，不用红色。
//  （超过目标时的那句温和说明属于「热量提示」，以后统一放在提示文案文件里，可以在设置里关掉）
//

import SwiftUI

struct DayProgressCard: View {
    let consumed: NutrientValues  // 这一天已经记录的合计
    let bodyInfo: BodyInfo
    let isToday: Bool  // 看的是不是今天：文字不一样

    private var targets: DailyTargets { NutritionCalculator.targets(for: bodyInfo) }
    private var progress: DayProgress { DietLogMath.progress(consumed: consumed, targets: targets) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline
            ProgressView(value: progress.kcalFraction)
            Text("已记录 \(progress.consumedKcal.noDecimal) · \(isToday ? "目标" : "按当前目标") \(progress.targetKcal.noDecimal) 千卡")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                MacroProgress(name: "蛋白质", consumed: consumed.proteinG, target: targets.proteinG, fraction: progress.proteinFraction, color: .blue)
                MacroProgress(name: "碳水", consumed: consumed.carbsG, target: targets.carbsG, fraction: progress.carbsFraction, color: .orange)
                MacroProgress(name: "脂肪", consumed: consumed.fatG, target: targets.fatG, fraction: progress.fatFraction, color: .pink)
            }
        }
        .padding(.vertical, 4)
    }

    /// 大字：还可以吃 / 比目标少（往日）/ 比目标多 / 刚好达到目标
    @ViewBuilder
    private var headline: some View {
        let remaining = progress.remainingKcal  // 整数，负数表示多了
        if remaining == 0 {
            Text("刚好达到目标")
                .font(.title2.bold())
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(remaining > 0 ? (isToday ? "还可以吃" : "比目标少") : "比目标多")
                    .foregroundStyle(.secondary)
                Text(abs(remaining).noDecimal)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    // 多了的时候数字也用灰色，不用红色
                    .foregroundStyle(remaining > 0 ? Color.primary : Color.secondary)
                Text("千卡")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 一种营养素的进度：「29 / 120 克」+ 细进度条 + 名称
private struct MacroProgress: View {
    let name: String
    let consumed: Double
    let target: Double
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(consumed.noDecimal) / \(target.noDecimal) 克")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(color)
            ProgressView(value: fraction)
                .tint(color)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("今天还可以吃") {
    List {
        DayProgressCard(
            consumed: NutrientValues(caloriesKcal: 572, proteinG: 28.6, carbsG: 52.1, fatG: 27.4),
            bodyInfo: SampleData.profile.bodyInfo, isToday: true)
    }
}

#Preview("比目标多") {
    List {
        DayProgressCard(
            consumed: NutrientValues(caloriesKcal: 3000, proteinG: 150, carbsG: 380, fatG: 90),
            bodyInfo: SampleData.profile.bodyInfo, isToday: true)
    }
}
