//
//  MealRow.swift
//  FoodTracker
//
//  「今日饮食」卡片里的几种行：
//  - MealHeaderRow：一餐的小标题（图标、早餐 / 午餐…、这一餐的千卡），两餐之间用一条很淡的线隔开
//  - MealRow：一条记录（名称、千卡，下面一行是重量和三大营养素）
//  - EmptyMealsRow：还没有记录时的说明
//  层级靠字号、字重和留白，不靠很多线条。
//

import SwiftUI

/// 一条记录：名称、千卡，下面一行是重量和三大营养素
struct MealRow: View {
    let entry: FoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text(entry.name)
                    .font(AppTypography.itemName)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)  // 名字很长时最多两行
                Spacer(minLength: AppSpacing.sm)
                Text("\(entry.caloriesKcal.noDecimal) 千卡")
                    .font(AppTypography.number)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize()  // 千卡数永远完整显示，名字太长时让名字换行
            }
            // 说明占满整行宽度，不被右边的千卡数挤成两行
            if !detail.isEmpty {
                Text(detail)
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xxs + 2)
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

/// 一餐的小标题：图标、早餐 / 午餐…、这一餐合计的千卡。不是第一餐时，上面有一条很淡的分隔线
struct MealHeaderRow: View {
    let meal: MealType
    let kcal: Double
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if showsDivider {
                Rectangle()
                    .fill(AppColors.divider)
                    .frame(height: 1)
            }
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: meal.systemImage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColors.iconSecondary)
                    .accessibilityHidden(true)
                Text(meal.title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.sm)
                Text("\(kcal.noDecimal) 千卡")
                    .font(AppTypography.numberSmall)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.top, showsDivider ? AppSpacing.xs : AppSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 还没有记录：一句说明 + 怎么记（往日补记时说「用上方的快速记录」）
struct EmptyMealsRow: View {
    let isToday: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(isToday ? "今天还没有记录" : "这一天没有记录")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
            Text(isToday ? "拍一张餐食照片，或点「手动」。" : "可以用上方的「快速记录」补记。")
                .font(AppTypography.detail)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
        .accessibilityElement(children: .combine)
    }
}
