//
//  DayProgressCard.swift
//  FoodTracker
//
//  「今日」页顶部的卡片：左边一只碗（吃了目标的几成就装到几成，和 App 图标是同一只碗），
//  右边是还可以吃多少；下面是三大营养素的进度。右上角的 ⓘ 打开「每日目标是怎么算的」。
//  超过目标时只用灰色写出多了多少，不用红色；碗也只是满碗，不会「溢出来」。
//  （超过目标时的那句温和说明属于「热量提示」，以后统一放在提示文案文件里，可以在设置里关掉）
//

import SwiftUI

struct DayProgressCard: View {
    let consumed: NutrientValues  // 这一天已经记录的合计
    let bodyInfo: BodyInfo
    let isToday: Bool  // 看的是不是今天：文字不一样
    let onExplain: () -> Void  // 点右上角的 ⓘ

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40  // 大数字跟着系统字号一起变大
    @ScaledMetric(relativeTo: .body) private var bowlWidth: CGFloat = 104
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var targets: DailyTargets { NutritionCalculator.targets(for: bodyInfo) }
    private var progress: DayProgress { DietLogMath.progress(consumed: consumed, targets: targets) }

    var body: some View {
        let large = dynamicTypeSize.isAccessibilitySize
        // 字号特别大时：碗放到数字上面，三种营养素改成上下排，免得挤在一行里显示不全
        let topLayout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))
        let macroLayout = large ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .bottom))
        VStack(alignment: .leading, spacing: 16) {
            topLayout {
                BowlGauge(fraction: progress.kcalFraction)
                    .frame(width: min(bowlWidth, 150))  // 跟着字号变大，但最大 150：字特别大时碗不用那么大
                VStack(alignment: .leading, spacing: 6) {
                    headline
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
                    .fixedSize(horizontal: false, vertical: true)  // 放不下时换行，不显示成「…」
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 平时文字在碗的右边，右上角给 ⓘ 留出位置；字特别大时文字在碗下面，ⓘ 在碗的右边，文字能用满整行
            .padding(.trailing, large ? 0 : 44)
            .overlay(alignment: .topTrailing) { explainButton }
            macroLayout {
                MacroProgress(name: String(localized: "蛋白质"), consumed: consumed.proteinG, target: targets.proteinG, fraction: progress.proteinFraction, color: Theme.protein)
                MacroProgress(name: String(localized: "碳水"), consumed: consumed.carbsG, target: targets.carbsG, fraction: progress.carbsFraction, color: Theme.carbs)
                MacroProgress(name: String(localized: "脂肪"), consumed: consumed.fatG, target: targets.fatG, fraction: progress.fatFraction, color: Theme.fat)
            }
        }
        .padding(.vertical, 6)
    }

    /// 还可以吃 / 比目标少（往日）/ 比目标多：上面一行小字说明，下面是大数字
    @ViewBuilder
    private var headline: some View {
        let remaining = progress.remainingKcal  // 负数表示多了
        if remaining == 0 {
            Text("刚好达到目标")
                .font(.title2.bold())
        } else {
            let number = abs(remaining).noDecimal
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if remaining < 0 {
                        Text("比目标多")
                    } else if isToday {
                        Text("还可以吃")
                    } else {
                        Text("比目标少")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(number)
                        .font(.system(size: heroSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        // 多了的时候数字也用灰色，不用红色
                        .foregroundStyle(remaining > 0 ? Color.primary : Color.secondary)
                    Text("千卡")
                        .foregroundStyle(.secondary)
                }
            }
            // 旁白把这一块读成一整句：「还可以吃 798 千卡」（英文是「798 kcal left」）
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySentence(remaining: remaining, number: number))
        }
    }

    private func accessibilitySentence(remaining: Double, number: String) -> Text {
        if remaining < 0 { return Text("比目标多 \(number) 千卡") }
        return isToday ? Text("还可以吃 \(number) 千卡") : Text("比目标少 \(number) 千卡")
    }

    /// 右上角的 ⓘ：打开「每日目标是怎么算的」。图标小，能点的范围有 44 × 44
    private var explainButton: some View {
        Button(action: onExplain) {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(Color(.secondaryLabel))  // 灰色：不抢主色按钮的风头
                .frame(width: 44, height: 44, alignment: .topTrailing)
                .contentShape(Rectangle())
        }
        // 放在列表的一行里：只有点到这个按钮才打开，点卡片别的地方没有反应
        .buttonStyle(.borderless)
        .accessibilityLabel("每日目标是怎么算的？")
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
            // 数字用正常的文字颜色；颜色只给下面的进度条（彩色的小字不好读，也像可以点的链接）
            Text("\(consumed.noDecimal) / \(target.noDecimal) 克")
                .font(.subheadline.monospacedDigit())
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
            bodyInfo: SampleData.profile.bodyInfo, isToday: true, onExplain: {})
    }
}

#Preview("比目标多") {
    List {
        DayProgressCard(
            consumed: NutrientValues(caloriesKcal: 3000, proteinG: 150, carbsG: 380, fatG: 90),
            bodyInfo: SampleData.profile.bodyInfo, isToday: true, onExplain: {})
    }
}
