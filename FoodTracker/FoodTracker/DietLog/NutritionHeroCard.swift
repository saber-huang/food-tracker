//
//  NutritionHeroCard.swift
//  FoodTracker
//
//  「今日」页的主卡片，也是这一页的视觉中心。看的顺序是：
//  1. 还可以吃多少（42pt 的大数字）
//  2. 下面一行小字「千卡可摄入」，再下面是已摄入、目标（很轻）
//  3. 三大营养素的细进度条
//  App 图标里的那只碗缩小放在数字右边，是品牌的点缀：先看到数字，之后才注意到碗。
//  右上角的 ⓘ 打开「每日目标是怎么算的」。
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
    @ScaledMetric(relativeTo: .body) private var bowlWidth: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isToday: Bool { DayMath.startOfDay(day) == DayMath.startOfDay(today) }
    private var targets: DailyTargets { NutritionCalculator.targets(for: bodyInfo) }
    private var progress: DayProgress { DietLogMath.progress(consumed: consumed, targets: targets) }

    var body: some View {
        let large = dynamicTypeSize.isAccessibilitySize
        // 字号特别大时：碗放到数字下面，统计和三种营养素改成上下排，免得挤在一行里显示不全
        let macroLayout =
            large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: AppSpacing.md))
        let statsLayout =
            large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AppSpacing.lg))

        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(alignment: .center) {
                Text(DayMath.dayTitle(for: day, today: today))
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: AppSpacing.xs)
                explainButton
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .center, spacing: AppSpacing.md) {
                    headline
                    Spacer(minLength: 0)
                    if !large { bowl }
                }
                if large { bowl }

                // 已摄入、目标：一行小字，不和大数字抢
                statsLayout {
                    StatInline(label: String(localized: "已摄入"), value: progress.consumedKcal.noDecimal)
                    // 往日也按现在的目标比较，所以写明「当前目标」
                    StatInline(
                        label: isToday ? String(localized: "目标") : String(localized: "当前目标"),
                        value: progress.targetKcal.noDecimal)
                }
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
        .padding(AppSpacing.heroPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(elevated: true)
    }

    /// 碗：品牌的点缀，比数字小、稍微淡一点
    private var bowl: some View {
        BowlGauge(fraction: progress.kcalFraction)
            .frame(width: min(bowlWidth, 96))
            .opacity(0.9)
    }

    /// 大数字 + 下面一行说明：还可以吃 / 比目标少（往日）/ 比目标多 / 刚好达到目标
    private var headline: some View {
        let remaining = progress.remainingKcal  // 负数表示多了
        let number = abs(remaining).noDecimal
        return VStack(alignment: .leading, spacing: 2) {
            Text(number)
                .font(AppTypography.heroNumber(size: heroSize))
                .tracking(0.6)
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

/// 一行里的一个小统计：「已摄入 1,144 千卡」，说明是灰色、数字是正文颜色，都是小字
private struct StatInline: View {
    let label: String
    let value: String  // 排好版的千卡数

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
            Text(label)
                .foregroundStyle(AppColors.textSecondary)
            Text("\(value) 千卡")
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
        }
        .font(AppTypography.detail)
        .accessibilityElement(children: .combine)
    }
}

/// 一种营养素的进度：名称、「57 / 120 克」（只有 57 是大一点的字）、细进度条。
/// 数字用正常的文字颜色，颜色只给进度条
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
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(consumed.noDecimal)
                    .font(AppTypography.number)
                    .foregroundStyle(AppColors.textPrimary)
                Text("/ \(target.noDecimal) 克")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .monospacedDigit()
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
