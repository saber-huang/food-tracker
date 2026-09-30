//
//  EntryRow.swift
//  FoodTracker
//
//  「今日」列表里的一行：名称、热量，下面一行是重量和三大营养素。
//

import SwiftUI

struct EntryRow: View {
    let entry: FoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(entry.caloriesKcal.noDecimal) 千卡")
                    .font(.headline.monospacedDigit())
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())  // 整行都能点（第 5 步用）
    }

    /// 「约 150 克 · 蛋白质 3.9 · 碳水 38.1 · 脂肪 0.5 克」；不知道重量时省略重量
    private var detail: String {
        var parts: [String] = []
        if entry.source == .recipe { parts.append("来自食谱") }
        if let weight = entry.weightG { parts.append("约 \(weight.oneDecimal) 克") }
        parts.append("蛋白质 \(entry.proteinG.oneDecimal) · 碳水 \(entry.carbsG.oneDecimal) · 脂肪 \(entry.fatG.oneDecimal) 克")
        return parts.joined(separator: " · ")
    }
}
