//
//  MealCard.swift
//  FoodTracker
//
//  「今日饮食」里的每一餐（早餐、午餐、晚餐、加餐）：
//  - 记过的一餐是一张完整的卡片（底色比「快速记录」轻一档）：
//    MealCardHeader（餐次图标，图标底色是这一餐很淡的分类色；早餐 / 午餐…；这一餐的千卡）
//    MealRow（一条记录一行：名称，右边是千卡和小箭头；点一下修改，左滑删除）
//    AggregatedFoodRow（同一种食物记了几次时合并成一行「米饭 ×2」，点一下展开）+ MealMemberRow（展开后的每一条）
//    MealMacroFooter（最下面一行：这一餐的蛋白质、碳水、脂肪）
//  - 还没记的一餐最轻：没有底色、只有一圈很淡的边，EmptyMealRow「早餐 还没有记录」，右边一个 +，点了直接给这一餐手动添加
//  不读字也能一眼看出哪一餐吃了、哪一餐还没吃。层级靠底色、字号、颜色和缩进，不靠阴影和分隔线。
//  字号特别大（辅助功能字号）时，千卡放到名称下面一行：并排放的话名称会被挤成一个字一行。
//

import SwiftUI

/// 名称和千卡：平时并排（千卡靠右），字号特别大时上下两行（千卡在名称下面）
private struct NameAndKcalLayout<Name: View, Kcal: View>: View {
    @ViewBuilder let name: Name
    @ViewBuilder let kcal: Kcal

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                name
                kcal
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                name
                Spacer(minLength: AppSpacing.xs)
                kcal
            }
        }
    }
}

/// 记过的一餐的第一行：图标、早餐 / 午餐…，右边是这一餐合计的千卡
struct MealCardHeader: View {
    let meal: MealType
    let kcal: Double

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            AppIconTile(systemImage: meal.systemImage, tint: meal.tint)
            NameAndKcalLayout {
                Text(meal.title)
                    .font(AppTypography.mealTitle)
                    .foregroundStyle(AppColors.textPrimary)
            } kcal: {
                Text("\(kcal.noDecimal) 千卡")
                    .font(AppTypography.number)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// 一条记录：名称，右边是千卡和小箭头（点了可以修改）
struct MealRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.xs) {
            NameAndKcalLayout {
                Text(entry.name)
                    .font(AppTypography.itemName)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)  // 名字很长时最多两行
            } kcal: {
                Text("\(entry.caloriesKcal.noDecimal) 千卡")
                    .font(AppTypography.numberSmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize()  // 千卡数永远完整显示，名字太长时让名字换行
            }
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

/// 同一种食物记了几次（名字一样、份量和热量差不多）：合并成一行「米饭 ×2」，右边是合计的千卡。
/// 点一下展开，下面列出每一条（可以分别修改、删除）；再点一下收起
struct AggregatedFoodRow: View {
    let name: String
    let count: Int
    let totalKcal: Double
    let isExpanded: Bool

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.xs) {
            NameAndKcalLayout {
                // 「×2」紧跟在名字后面、跟着一起换行，不会被挤到单独一行
                (Text(name).foregroundStyle(AppColors.textPrimary)
                    + Text(verbatim: " ×\(count)").font(AppTypography.numberSmall).foregroundStyle(AppColors.textSecondary))
                    .font(AppTypography.itemName)
                    .lineLimit(2)
            } kcal: {
                Text("\(totalKcal.noDecimal) 千卡")
                    .font(AppTypography.numberSmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize()
            }
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(name)，\(count) 份，共 \(totalKcal.noDecimal) 千卡"))
        .accessibilityHint(isExpanded ? String(localized: "收起") : String(localized: "展开查看每一条"))
    }
}

/// 合并的那一行展开后的每一条：份量和千卡（名字和上面一样，不重复写），点一下修改
struct MealMemberRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.xs) {
            NameAndKcalLayout {
                Text(detail)
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
            } kcal: {
                Text("\(entry.caloriesKcal.noDecimal) 千卡")
                    .font(AppTypography.numberSmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize()
            }
            AppChevron()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(entry.name)，\(detail)"))
        .accessibilityHint("修改这一条")
    }

    /// 「约 150 克 · 来自食谱」；什么都没有时写「1 份」
    private var detail: String {
        var parts: [String] = []
        if let weight = entry.weightG { parts.append(String(localized: "约 \(weight.oneDecimal) 克")) }
        if entry.source == .recipe { parts.append(String(localized: "来自食谱")) }
        return parts.isEmpty ? String(localized: "1 份") : parts.joined(separator: " · ")
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

/// 还没记的一餐：最轻的一条（没有底色，只有一圈很淡的边，见 DayLogView），「早餐  还没有记录」，右边一个 +（点整条都可以）
struct EmptyMealRow: View {
    let meal: MealType

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Image(systemName: meal.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(meal.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColors.textSecondary)
                Text("还没有记录")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textTertiary)
            }
            Spacer(minLength: AppSpacing.xs)
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.brand)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(AppColors.brand.opacity(0.35), lineWidth: 1))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(meal.title)，还没有记录")
        .accessibilityHint("手动添加\(meal.title)")
    }
}
