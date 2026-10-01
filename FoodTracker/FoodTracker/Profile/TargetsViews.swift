//
//  TargetsViews.swift
//  FoodTracker
//
//  显示每日目标的几个小组件，在引导页结果、「我的」页面和食谱详情页里共用。
//

import SwiftUI

/// 每日目标的完整展示：大号热量 + 三大营养素
struct TargetsSummaryView: View {
    let targets: DailyTargets

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(targets.calories.noDecimal)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("千卡 / 天")
                    .foregroundStyle(.secondary)
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
                .font(.headline.monospacedDigit())
            HStack(spacing: 5) {
                Capsule()
                    .fill(color)
                    .frame(width: 12, height: 4)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        // 旁白读成「蛋白质 120 克」
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(value) 克")
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
            .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
        }
    }
}
