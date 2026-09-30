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

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40  // 大数字跟着系统字号一起变大
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var targets: DailyTargets { NutritionCalculator.targets(for: bodyInfo) }
    private var progress: DayProgress { DietLogMath.progress(consumed: consumed, targets: targets) }

    var body: some View {
        // 字号特别大时三种营养素改成上下排，免得挤在一行里显示不全
        let macroLayout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .bottom))
        VStack(alignment: .leading, spacing: 12) {
            headline
            ProgressView(value: progress.kcalFraction)
                .accessibilityHidden(true)  // 旁白（VoiceOver）不读这条进度条：上下两行已经读出了数字
            // 两种情况各写成一整句，翻译时不会漏掉中间那个词（往日也按现在的目标比较，所以写明「按当前目标」）
            Group {
                if isToday {
                    Text("已记录 \(progress.consumedKcal.noDecimal) · 目标 \(progress.targetKcal.noDecimal) 千卡")
                } else {
                    Text("已记录 \(progress.consumedKcal.noDecimal) · 按当前目标 \(progress.targetKcal.noDecimal) 千卡")
                }
            }
                .font(.caption)
                .foregroundStyle(.secondary)
            macroLayout {
                MacroProgress(name: String(localized: "蛋白质"), consumed: consumed.proteinG, target: targets.proteinG, fraction: progress.proteinFraction, color: .blue)
                MacroProgress(name: String(localized: "碳水"), consumed: consumed.carbsG, target: targets.carbsG, fraction: progress.carbsFraction, color: .orange)
                MacroProgress(name: String(localized: "脂肪"), consumed: consumed.fatG, target: targets.fatG, fraction: progress.fatFraction, color: .pink)
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
            let number = Text(abs(remaining).noDecimal)
                .font(.system(size: heroSize, weight: .bold, design: .rounded))
                // 多了的时候数字也用灰色，不用红色
                .foregroundStyle(remaining > 0 ? Color.primary : Color.secondary)
            // 整句是一段文字：字号很大时像句子一样换行，数字不会被拆开；旁白也一次读完。
            // 三种情况各写成一整句，翻译成英文时可以调整语序（英文是「798 kcal left」）
            Group {
                if remaining <= 0 {
                    Text("比目标多 \(number) 千卡")
                } else if isToday {
                    Text("还可以吃 \(number) 千卡")
                } else {
                    Text("比目标少 \(number) 千卡")
                }
            }
            .foregroundStyle(.secondary)
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
        // 旁白把这一列读成一句「蛋白质 29 克，目标 120 克」（进度条不单独读）
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(consumed.noDecimal) 克，目标 \(target.noDecimal) 克")
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
