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
            Label(
                "为了安全，每日热量没有设得太低：我们把它调到了 \(targets.calorieFloor.noDecimal) 千卡。减脂慢一点更健康，也更容易坚持。",
                systemImage: "heart.circle"
            )
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
