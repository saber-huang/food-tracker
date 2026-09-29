//
//  ResultView.swift
//  FoodTracker
//
//  结果页：列出每种食物的营养数据、整餐合计，底部是「热量为 AI 估算」的提示。
//

import SwiftUI

struct ResultView: View {
    let result: AnalyzeResult
    let photo: UIImage?

    var body: some View {
        List {
            // 照片和 AI 的一句话总结
            Section {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text(result.message)
            }

            if result.isFood {
                Section("识别到的食物") {
                    // enumerated() 给每一项编个号，当作列表里的唯一标识
                    ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                        FoodRow(item: item)
                    }
                }
                Section("整餐合计") {
                    TotalView(total: result.total)
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "没有识别到食物",
                        systemImage: "questionmark.circle",
                        description: Text("请返回，换一张清楚的餐食照片再试。")
                    )
                }
            }
        }
        .navigationTitle("识别结果")
        .navigationBarTitleDisplayMode(.inline)
        // 固定在页面最底部的提示
        .safeAreaInset(edge: .bottom) {
            Text("热量为 AI 估算，仅供参考")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.bar)
        }
    }
}

/// 一种食物占一行：名称、可信度、热量、重量、三大营养素
private struct FoodRow: View {
    let item: FoodItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.name)
                    .font(.headline)
                ConfidenceBadge(confidence: item.confidence)
                Spacer()
                Text("\(item.caloriesKcal.noDecimal) 千卡")
                    .font(.headline)
            }
            Text("约 \(item.weightG.noDecimal) 克")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("蛋白质 \(item.proteinG.oneDecimal) 克 · 碳水 \(item.carbsG.oneDecimal) 克 · 脂肪 \(item.fatG.oneDecimal) 克")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// 可信度小标签：高是绿色，中是橙色，低是红色
private struct ConfidenceBadge: View {
    let confidence: Confidence

    private var color: Color {
        switch confidence {
        case .high: .green
        case .medium: .orange
        case .low: .red
        }
    }

    var body: some View {
        Text(confidence.label)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// 整餐合计：大号的总热量，下面是三大营养素
private struct TotalView: View {
    let total: MealTotal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(total.caloriesKcal.noDecimal)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("千卡")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("共约 \(total.weightG.noDecimal) 克")
                    .foregroundStyle(.secondary)
            }
            HStack {
                MacroView(name: "蛋白质", grams: total.proteinG, color: .blue)
                MacroView(name: "碳水", grams: total.carbsG, color: .orange)
                MacroView(name: "脂肪", grams: total.fatG, color: .pink)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 一种营养素：数值 + 名称
private struct MacroView: View {
    let name: String
    let grams: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(grams.oneDecimal) 克")
                .font(.headline)
                .foregroundStyle(color)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Xcode 右侧画布里的预览，用假数据看看页面长什么样
#Preview("有食物") {
    NavigationStack {
        ResultView(
            result: AnalyzeResult(
                isFood: true,
                message: "一份米饭配宫保鸡丁",
                items: [
                    FoodItem(
                        name: "米饭", weightG: 150, caloriesKcal: 174, proteinG: 3.9,
                        carbsG: 38.1, fatG: 0.5, confidence: .high),
                    FoodItem(
                        name: "宫保鸡丁", weightG: 200, caloriesKcal: 398, proteinG: 24.7,
                        carbsG: 14, fatG: 26.9, confidence: .medium),
                ],
                total: MealTotal(weightG: 350, caloriesKcal: 572, proteinG: 28.6, carbsG: 52.1, fatG: 27.4),
                model: "claude-opus-5-5"
            ),
            photo: nil
        )
    }
}

#Preview("没有食物") {
    NavigationStack {
        ResultView(
            result: AnalyzeResult(
                isFood: false,
                message: "这是一张风景照，没有食物。",
                items: [],
                total: MealTotal(weightG: 0, caloriesKcal: 0, proteinG: 0, carbsG: 0, fatG: 0),
                model: "claude-opus-5-5"
            ),
            photo: nil
        )
    }
}
