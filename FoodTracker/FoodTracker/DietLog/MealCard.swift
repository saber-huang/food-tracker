//
//  MealCard.swift
//  FoodTracker
//
//  「今日饮食」里每一餐是一张卡片（早餐、午餐、晚餐、加餐各一张）：
//  - MealCardHeader：卡片的第一行。左边是餐次的小图标，标题下面一行是这一餐的三大营养素，右边是这一餐的千卡
//  - MealRow：这一餐里的一条记录（名称、重量，右边是千卡和小箭头），往右缩进，和标题对齐；点一下修改，左滑删除
//  - EmptyMealCard：还没有记录的一餐，一行「还没有记录」，右边一个 +，点了直接给这一餐手动添加
//  层级靠字号、颜色和缩进，不靠很多分隔线。
//

import SwiftUI

/// 一餐的卡片标题：图标、早餐 / 午餐…、这一餐的营养素，右边是这一餐合计的千卡
struct MealCardHeader: View {
    let meal: MealType
    let total: NutrientValues  // 这一餐的合计

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            AppIconTile(systemImage: meal.systemImage)
            VStack(alignment: .leading, spacing: 2) {
                // 千卡和标题在同一行，下面的营养素可以用满整行，不会被挤成两行
                HStack(alignment: .firstTextBaseline) {
                    Text(meal.title)
                        .font(AppTypography.mealTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer(minLength: AppSpacing.xs)
                    Text("\(total.caloriesKcal.noDecimal) 千卡")
                        .font(AppTypography.number)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize()
                }
                // 三种营养素都是 0（只填了热量）时不显示，免得看起来像「没有蛋白质、碳水、脂肪」
                if total.proteinG > 0 || total.carbsG > 0 || total.fatG > 0 {
                    Text("蛋白质 \(total.proteinG.noDecimal) · 碳水 \(total.carbsG.noDecimal) · 脂肪 \(total.fatG.noDecimal) 克")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 一条记录：名称、重量（从食谱记的会写「来自食谱」），右边是千卡和小箭头（点了可以修改）
struct MealRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(AppTypography.itemName)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)  // 名字很长时最多两行
                if !detail.isEmpty {
                    Text(detail)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer(minLength: AppSpacing.xs)
            Text("\(entry.caloriesKcal.noDecimal) 千卡")
                .font(AppTypography.numberSmall)
                .monospacedDigit()
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize()  // 千卡数永远完整显示，名字太长时让名字换行
            AppChevron()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())  // 整行都能点
    }

    /// 「来自食谱 · 约 150 克」；不知道重量、也不是食谱时什么都不写（营养素写在这一餐的标题下面）
    private var detail: String {
        var parts: [String] = []
        if entry.source == .recipe { parts.append(String(localized: "来自食谱")) }
        if let weight = entry.weightG { parts.append(String(localized: "约 \(weight.oneDecimal) 克")) }
        return parts.joined(separator: " · ")
    }
}

/// 还没有记录的一餐：图标、餐次、「还没有记录」，右边一个 +（点整行都可以）
struct EmptyMealCard: View {
    let meal: MealType

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            AppIconTile(systemImage: meal.systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title)
                    .font(AppTypography.mealTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("还没有记录")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: AppSpacing.xs)
            AppIconTile(systemImage: "plus", size: 32, tint: AppColors.brandSoft, iconColor: AppColors.brand)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(meal.title)，还没有记录")
        .accessibilityHint("手动添加\(meal.title)")
    }
}
