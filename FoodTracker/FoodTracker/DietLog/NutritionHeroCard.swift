//
//  NutritionHeroCard.swift
//  FoodTracker
//
//  「今日」页的主卡片，也是这一页的视觉中心：
//  最上面一行是哪一天（今天 / 昨天 / 9月28日 周一）和 ⓘ（打开「每日目标是怎么算的」）；
//  中间是还可以吃多少（大数字），旁边是 App 图标里的那只碗，吃了目标的几成就装到几成；
//  下面是已摄入、目标，最后是三大营养素的细进度条。
//  超过目标时只用灰色写出多了多少，不用红色；碗也只是满碗，不会「溢出来」。
//

import SwiftUI

struct NutritionHeroCard: View {
    let consumed: NutrientValues  // 这一天已经记录的合计
    let bodyInfo: BodyInfo
    let day: Date  // 卡片显示的是哪一天
    let today: Date
    let onExplain: () -> Void  // 点右上角的 ⓘ

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = AppTypography.heroNumberSize
    @ScaledMetric(relativeTo: .body) private var bowlWidth: CGFloat = 88
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isToday: Bool { DayMath.startOfDay(day) == DayMath.startOfDay(today) }
    private var targets: DailyTargets { NutritionCalculator.targets(for: bodyInfo) }
    private var progress: DayProgress { DietLogMath.progress(consumed: consumed, targets: targets) }

    var body: some View {
        let large = dynamicTypeSize.isAccessibilitySize
        // 字号特别大时：碗放到数字上面，三种营养素改成上下排，免得挤在一行里显示不全
        let mainLayout =
            large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.md))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AppSpacing.md))
        let macroLayout =
            large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.md))

        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(alignment: .center) {
                Text(DayMath.dayTitle(for: day, today: today))
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: AppSpacing.xs)
                explainButton
            }

            mainLayout {
                headline
                if !large { Spacer(minLength: 0) }
                BowlGauge(fraction: progress.kcalFraction)
                    .frame(width: min(bowlWidth, 128))  // 碗是品牌的点缀，比数字小
            }

            // 字号特别大时「已摄入」「目标」上下排，数字不会被挤成两行
            let statsLayout =
                large
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.sm))
                : AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.xxl))
            statsLayout {
                StatItem(label: String(localized: "已摄入"), value: progress.consumedKcal.noDecimal)
                // 往日也按现在的目标比较，所以写明「当前目标」
                StatItem(
                    label: isToday ? String(localized: "目标") : String(localized: "当前目标"),
                    value: progress.targetKcal.noDecimal)
            }

            macroLayout {
                MacroProgress(
                    name: String(localized: "蛋白质"), consumed: consumed.proteinG, target: targets.proteinG,
                    fraction: progress.proteinFraction, color: AppColors.protein)
                MacroProgress(
                    name: String(localized: "碳水"), consumed: consumed.carbsG, target: targets.carbsG,
                    fraction: progress.carbsFraction, color: AppColors.carbs)
                MacroProgress(
                    name: String(localized: "脂肪"), consumed: consumed.fatG, target: targets.fatG,
                    fraction: progress.fatFraction, color: AppColors.fat)
            }
        }
        .padding(AppSpacing.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(radius: AppRadius.hero, elevated: true)
    }

    /// 大数字 + 下面一行说明：还可以吃 / 比目标少（往日）/ 比目标多 / 刚好达到目标
    private var headline: some View {
        let remaining = progress.remainingKcal  // 负数表示多了
        let number = abs(remaining).noDecimal
        return VStack(alignment: .leading, spacing: 2) {
            Text(number)
                .font(AppTypography.heroNumber(size: heroSize))
                .monospacedDigit()
                // 多了的时候数字用灰色，不用红色
                .foregroundStyle(remaining >= 0 ? AppColors.textPrimary : AppColors.textSecondary)
            Group {
                if remaining == 0 {
                    Text("刚好达到目标")
                } else if remaining < 0 {
                    Text("千卡，比目标多")
                } else if isToday {
                    Text("千卡可摄入")
                } else {
                    Text("千卡，比目标少")
                }
            }
            .font(AppTypography.heroCaption)
            .foregroundStyle(AppColors.textSecondary)
        }
        // 旁白把这一块读成一整句：「还可以吃 798 千卡」（英文是「798 kcal left」）
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySentence(remaining: remaining, number: number))
    }

    private func accessibilitySentence(remaining: Double, number: String) -> Text {
        if remaining == 0 { return Text("刚好达到目标") }
        if remaining < 0 { return Text("比目标多 \(number) 千卡") }
        return isToday ? Text("还可以吃 \(number) 千卡") : Text("比目标少 \(number) 千卡")
    }

    /// 右上角的 ⓘ：打开「每日目标是怎么算的」。图标小，能点的范围有 44 × 44
    private var explainButton: some View {
        Button(action: onExplain) {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        // 放在列表的一行里：只有点到这个按钮才打开，点卡片别的地方没有反应
        .buttonStyle(.borderless)
        .padding(-AppSpacing.sm)  // 点击范围够大，但不把这一行撑高
        .accessibilityLabel("每日目标是怎么算的？")
    }
}

/// 一个小统计：上面一行小字说明，下面是数字（已摄入、目标）
private struct StatItem: View {
    let label: String
    let value: String  // 排好版的千卡数

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            Text("\(value) 千卡")
                .font(AppTypography.number)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 一种营养素的进度：名称、「29 / 120 克」、细进度条。数字用正常的文字颜色，颜色只给进度条
struct MacroProgress: View {
    let name: String
    let consumed: Double
    let target: Double
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            Text("\(consumed.noDecimal) / \(target.noDecimal) 克")
                .font(AppTypography.number)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)  // 三位数的克数在小屏手机上也放得下
            SlimProgressBar(fraction: fraction, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 旁白把这一列读成一句「蛋白质 29 克，目标 120 克」（进度条不单独读）
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(consumed.noDecimal) 克，目标 \(target.noDecimal) 克")
    }
}

/// 细进度条：4pt 高，两头圆；底槽是燕麦灰
struct SlimProgressBar: View {
    let fraction: Double  // 0～1
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(AppColors.surfaceMuted)
                if clamped > 0 {
                    // 吃得很少时也至少露出一个小圆头，看得出「已经开始了」
                    Capsule().fill(color).frame(width: max(proxy.size.width * clamped, 4))
                }
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: fraction)
        .accessibilityHidden(true)
    }
}

#Preview("今天还可以吃") {
    ZStack {
        AppBackground()
        NutritionHeroCard(
            consumed: NutrientValues(caloriesKcal: 1144, proteinG: 57, carbsG: 104, fatG: 55),
            bodyInfo: SampleData.profile.bodyInfo, day: .now, today: .now, onExplain: {}
        )
        .padding(AppSpacing.pageMargin)
    }
}

#Preview("比目标多") {
    ZStack {
        AppBackground()
        NutritionHeroCard(
            consumed: NutrientValues(caloriesKcal: 3000, proteinG: 150, carbsG: 380, fatG: 90),
            bodyInfo: SampleData.profile.bodyInfo, day: .now, today: .now, onExplain: {}
        )
        .padding(AppSpacing.pageMargin)
    }
}
