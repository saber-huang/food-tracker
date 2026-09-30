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
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())  // 整行都能点
    }

    /// 「约 150 克 · 蛋白质 3.9 · 碳水 38.1 · 脂肪 0.5 克」；不知道重量时省略重量，
    /// 三种营养素都是 0（只填了热量）时省略营养素，免得看起来像「没有蛋白质、碳水、脂肪」
    private var detail: String {
        var parts: [String] = []
        if entry.source == .recipe { parts.append(String(localized: "来自食谱")) }
        if let weight = entry.weightG { parts.append(String(localized: "约 \(weight.oneDecimal) 克")) }
        if entry.proteinG > 0 || entry.carbsG > 0 || entry.fatG > 0 {
            parts.append(String(localized: "蛋白质 \(entry.proteinG.oneDecimal) · 碳水 \(entry.carbsG.oneDecimal) · 脂肪 \(entry.fatG.oneDecimal) 克"))
        }
        return parts.joined(separator: " · ")
    }
}
