//
//  TargetsViews.swift
//  FoodTracker
//
//  显示每日目标的几个小组件，在引导页结果、「我的」页面和食谱详情页里共用。
//

import SwiftUI

/// 每日目标的完整展示：大号热量 + 三大营养素（数字用 App 统一的圆体等宽数字，单位小一号、浅一点）
struct TargetsSummaryView: View {
    let targets: DailyTargets

    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                Text(targets.calories.noDecimal)
                    .font(AppTypography.heroNumber(size: numberSize))
                    .foregroundStyle(AppColors.textPrimary)
                Text("千卡 / 天")
                    .font(AppTypography.heroCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            HStack {
                NutrientColumn(name: String(localized: "蛋白质"), value: targets.proteinG.noDecimal, color: AppColors.protein)
                NutrientColumn(name: String(localized: "碳水"), value: targets.carbsG.noDecimal, color: AppColors.carbs)
                NutrientColumn(name: String(localized: "脂肪"), value: targets.fatG.noDecimal, color: AppColors.fat)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 一种营养素：克数 + 名称。数字用正常的文字颜色（彩色的字不好读，也容易被当成可以点的链接），
/// 名称前面的小色条告诉你是哪一种（和「今日」卡片里的进度条同一个颜色）
struct NutrientColumn: View {
    let name: String
    let value: String  // 已经排好版的克数，比如「120」「38.1」
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value) 克")
                .font(AppTypography.number)
                .foregroundStyle(AppColors.textPrimary)
            HStack(spacing: 5) {
                Capsule()
                    .fill(color)
                    .frame(width: 12, height: 4)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        // 旁白读成「蛋白质 120 克」
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(value) 克")
    }
}

/// 一种营养素的目标：上面是克数，下面是小色条 + 名称（左对齐）。
/// 「我的」页的每日目标和食谱详情都用它，两边看起来一样
struct MacroStat: View {
    let name: String
    let grams: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(grams.noDecimal) 克")
                .font(AppTypography.number)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
            HStack(spacing: 6) {
                Capsule()
                    .fill(color)
                    .frame(width: 10, height: 4)
                Text(name)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 旁白读成「蛋白质 120 克」
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(grams.noDecimal) 克")
    }
}

/// 三种营养素的目标并排（蛋白质、碳水、脂肪）。字号特别大时改成上下三行，免得挤成「蛋白 / 质」
struct MacroStatsRow: View {
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                MacroStatLine(name: String(localized: "蛋白质"), grams: proteinG, color: AppColors.protein)
                MacroStatLine(name: String(localized: "碳水"), grams: carbsG, color: AppColors.carbs)
                MacroStatLine(name: String(localized: "脂肪"), grams: fatG, color: AppColors.fat)
            }
        } else {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                MacroStat(name: String(localized: "蛋白质"), grams: proteinG, color: AppColors.protein)
                MacroStat(name: String(localized: "碳水"), grams: carbsG, color: AppColors.carbs)
                MacroStat(name: String(localized: "脂肪"), grams: fatG, color: AppColors.fat)
            }
        }
    }
}

/// 字号特别大时的一行：小色条 + 名称，右边是克数
private struct MacroStatLine: View {
    let name: String
    let grams: Double
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Capsule()
                .fill(color)
                .frame(width: 10, height: 4)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 6 }
            Text(name)
                .foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: AppSpacing.xs)
            Text("\(grams.noDecimal) 克")
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
        }
        .font(AppTypography.number)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(grams.noDecimal) 克")
    }
}

/// 碰到安全下限时的温和提示
struct FloorNotice: View {
    let targets: DailyTargets

    var body: some View {
        if targets.isRaisedToFloor {
            // 平静的说明，不用红色或橙色；也不显示公式算出来的那个更低的数
            Label(
                "为了让你吃够身体需要的营养，我们把每日目标保持在 \(targets.calorieFloor.noDecimal) 千卡，这是没有医生或营养师指导时通常建议的最低摄入量。想让进度快一点，可以在日常多活动一些，比如多走走路。",
                systemImage: "heart.circle"
            )
            .font(.callout)
            .foregroundStyle(AppColors.textSecondary)
        }
    }
}

/// 针对这个人和这个目标的温和提示（可能有多条，也可能没有）
struct GoalNotesView: View {
    let bodyInfo: BodyInfo

    var body: some View {
        ForEach(ProfileValidator.goalNotes(for: bodyInfo), id: \.self) { note in
            Label(note, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
