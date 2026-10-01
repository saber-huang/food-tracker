//
//  MealCard.swift
//  FoodTracker
//
//  「今日饮食」里的每一餐（早餐、午餐、晚餐、加餐）：
//  - 记过的一餐是一张完整的白卡片：
//    MealCardHeader（餐次图标、早餐 / 午餐…、这一餐的千卡）
//    MealRow（一条记录一行：名称，右边是千卡和小箭头；点一下修改，左滑删除）
//    MealMacroFooter（最下面一行：这一餐的蛋白质、碳水、脂肪）
//  - 还没记的一餐是一条更轻的半透明窄条 EmptyMealRow：「早餐 还没有记录」，右边一个 +，点了直接给这一餐手动添加
//  扫一眼就能看出哪一餐还需要记。层级靠字号、颜色和缩进，不靠很多分隔线。
//

import SwiftUI

/// 记过的一餐的第一行：图标、早餐 / 午餐…，右边是这一餐合计的千卡
struct MealCardHeader: View {
    let meal: MealType
    let kcal: Double

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            AppIconTile(systemImage: meal.systemImage)
            Text(meal.title)
                .font(AppTypography.mealTitle)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: AppSpacing.xs)
            Text("\(kcal.noDecimal) 千卡")
                .font(AppTypography.number)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 一条记录：名称，右边是千卡和小箭头（点了可以修改）
struct MealRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Text(entry.name)
                .font(AppTypography.itemName)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)  // 名字很长时最多两行
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
        // 旁白多读一点：重量、是不是来自食谱（屏幕上为了干净只写名称和千卡）
        .accessibilityElement(children: .combine)
        .accessibilityValue(detail)
    }

    /// 「来自食谱 · 约 150 克」：只给旁白读
    private var detail: String {
        var parts: [String] = []
        if entry.source == .recipe { parts.append(String(localized: "来自食谱")) }
        if let weight = entry.weightG { parts.append(String(localized: "约 \(weight.oneDecimal) 克")) }
        return parts.joined(separator: " · ")
    }
}

/// 记过的一餐的最后一行：这一餐的三大营养素（三种都是 0，也就是只填了热量时，DayLogView 不放这一行）
struct MealMacroFooter: View {
    let total: NutrientValues

    var body: some View {
        Text("蛋白质 \(total.proteinG.noDecimal) · 碳水 \(total.carbsG.noDecimal) · 脂肪 \(total.fatG.noDecimal) 克")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 还没记的一餐：一条窄窄的半透明条，「早餐  还没有记录」，右边一个 +（点整条都可以）
struct EmptyMealRow: View {
    let meal: MealType

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Image(systemName: meal.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.iconSecondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(meal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("还没有记录")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: AppSpacing.xs)
            AppIconTile(systemImage: "plus", size: 30, tint: AppColors.brandSoft, iconColor: AppColors.brand)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(meal.title)，还没有记录")
        .accessibilityHint("手动添加\(meal.title)")
    }
}
