//
//  TargetsViews.swift
//  FoodTracker
//
//  显示每日目标的几个小组件，在首页、引导页结果、「我的」页面里共用。
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
                NutrientColumn(name: "蛋白质", grams: targets.proteinG, color: .blue)
                NutrientColumn(name: "碳水", grams: targets.carbsG, color: .orange)
                NutrientColumn(name: "脂肪", grams: targets.fatG, color: .pink)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 一种营养素：克数 + 名称
struct NutrientColumn: View {
    let name: String
    let grams: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(grams.noDecimal) 克")
                .font(.headline)
                .foregroundStyle(color)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

/// 首页顶部的小卡片：一行显示今日目标，点「怎么算的」看说明
struct TargetsCard: View {
    let bodyInfo: BodyInfo

    private var targets: DailyTargets { NutritionCalculator.targets(for: bodyInfo) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("每日目标")
                    .font(.headline)
                Spacer()
                NavigationLink("怎么算的") {
                    ExplanationView(bodyInfo: bodyInfo)
                }
                .font(.subheadline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(targets.calories.noDecimal)
                    .font(.title.bold())
                Text("千卡")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("蛋白质 \(targets.proteinG.noDecimal) · 碳水 \(targets.carbsG.noDecimal) · 脂肪 \(targets.fatG.noDecimal) 克")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
