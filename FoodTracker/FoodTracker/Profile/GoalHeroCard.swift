//
//  GoalHeroCard.swift
//  FoodTracker
//
//  「我的」页最上面的主卡片：每日目标。看的顺序是大号的千卡 → 三大营养素 → （有的话）温和的说明。
//  和「今日」页的主卡片是同一种样子（大数字、很轻的阴影），三个标签页看起来是同一个 App。
//

import SwiftUI

struct GoalHeroCard: View {
    let targets: DailyTargets
    let bodyInfo: BodyInfo

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = AppTypography.heroNumberSize

    var body: some View {
        let notes = ProfileValidator.goalNotes(for: bodyInfo)
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text("每日目标")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(targets.calories.noDecimal)
                        .font(AppTypography.heroNumber(size: heroSize))
                        .tracking(0.6)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textPrimary)
                    Text("千卡 / 天")
                        .font(AppTypography.heroCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            MacroStatsRow(proteinG: targets.proteinG, carbsG: targets.carbsG, fatG: targets.fatG)

            // 碰到安全下限、或者对这个人有温和的提醒时，才在卡片下面写一小段（平时没有）
            if targets.isRaisedToFloor || !notes.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Rectangle()
                        .fill(AppColors.divider)
                        .frame(height: 1)
                    FloorNotice(targets: targets)
                    GoalNotesView(bodyInfo: bodyInfo)
                }
                .font(AppTypography.detail)
            }
        }
        .padding(AppSpacing.heroPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(elevated: true)
    }
}

/// 「我的」页卡片里的一行：左边名称，右边值（灰色）。每行至少 56pt 高
struct ProfileInfoRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.body)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: AppSpacing.sm)
            Text(value)
                .font(.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)  // 行高由列表的最小行高（56pt）决定
    }
}
