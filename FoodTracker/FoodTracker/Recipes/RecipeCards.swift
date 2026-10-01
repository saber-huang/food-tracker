//
//  RecipeCards.swift
//  FoodTracker
//
//  「食谱」页用到的几种卡片：
//  - RecipeGoalSummary：每日目标的摘要（辅助信息：小一号的燕麦色卡片，放在推荐下面）
//  - RecipeCard + RecipeCardFooter：一餐的推荐（餐次标签、菜名、热量、三大营养素、时间）。
//    整张卡片点了就打开做法（右边的小箭头表示能点）；下面一行只有一个次要的「换一个」
//  - EmptyRecipesCard：还没有推荐时的样子（空的碗 + 「生成一日三餐」）；生成中换成碗的加载动画和阶段说明
//  - RegenerateButton：已经有推荐时，下面一个不太大的「重新生成一日三餐」
//  - PreferenceSummary：饮食偏好的摘要（是设置条件，比推荐安静）
//  这里只负责样子；生成、换一个、打开详情都由 RecipesView 来做。
//

import SwiftUI

/// 每日目标的摘要：辅助信息，小一号的燕麦色卡片（圆角 20，不是白卡片）。
/// 第一行「减脂」和千卡，第二行三种营养素（小圆点 + 克数）
struct RecipeGoalSummary: View {
    let targets: DailyTargets
    let goalTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(goalTitle)
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: AppSpacing.xs)
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                    Text(targets.calories.noDecimal)
                        .font(AppTypography.number)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textPrimary)
                    Text("千卡")
                        .font(AppTypography.detail)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.md) { macroItems }
                VStack(alignment: .leading, spacing: AppSpacing.xxs) { macroItems }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(.muted)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var macroItems: some View {
        MacroDot(name: String(localized: "蛋白质"), grams: targets.proteinG, color: AppColors.protein)
        MacroDot(name: String(localized: "碳水"), grams: targets.carbsG, color: AppColors.carbs)
        MacroDot(name: String(localized: "脂肪"), grams: targets.fatG, color: AppColors.fat)
    }
}

/// 餐次的小标签：图标 + 早餐 / 午餐 / 晚餐，底色是这一餐很淡的分类色（奶油黄、鼠尾草、灰褐），扫一眼就分得开
struct MealSlotTag: View {
    let slot: MealSlot

    var body: some View {
        // 不用 Label：放在系统列表里时，Label 会给图标留出一大块位置，图标和字离得很远
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: slot.systemImage)
                .accessibilityHidden(true)
            Text(slot.title)
        }
        .font(AppTypography.caption.weight(.medium))
        .foregroundStyle(AppColors.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(slot.tint, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// 一餐的推荐：餐次标签和时间、菜名、热量、三大营养素
struct RecipeCard: View {
    let recipe: Recipe

    @ScaledMetric(relativeTo: .title) private var numberSize: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md - 2) {
            // 餐次标签和时间放一行；字号特别大时，时间放到标签下面（不会把「约 15 分钟」拆成两行）
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    MealSlotTag(slot: recipe.meal)
                    cookingTime
                }
            } else {
                HStack(alignment: .center) {
                    MealSlotTag(slot: recipe.meal)
                    Spacer(minLength: AppSpacing.xs)
                    cookingTime
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                // 卡片上最多两行，太长的菜名末尾省略（详情页里完整显示）
                Text(recipe.name)
                    .font(AppTypography.recipeName)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppSpacing.xs)
                AppChevron()  // 整张卡片都能点，打开做法
            }
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                Text(recipe.caloriesKcal.noDecimal)
                    .font(AppTypography.heroNumber(size: numberSize))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary)
                Text("千卡")
                    .font(AppTypography.heroCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            // 三大营养素：小圆点（颜色和首页一样）+ 文字，一行放下
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.md) { macroItems }
                VStack(alignment: .leading, spacing: AppSpacing.xxs) { macroItems }
            }
        }
        .padding(.top, AppSpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())  // 整张卡片都能点
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看做法")
    }

    /// 「🕘 约 15 分钟」
    private var cookingTime: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: "clock")
                .accessibilityHidden(true)
            Text("约 \(recipe.cookingMinutes) 分钟")
        }
        .font(AppTypography.caption)
        .foregroundStyle(AppColors.textSecondary)
    }

    @ViewBuilder
    private var macroItems: some View {
        MacroDot(name: String(localized: "蛋白质"), grams: recipe.proteinG, color: AppColors.protein)
        MacroDot(name: String(localized: "碳水"), grams: recipe.carbsG, color: AppColors.carbs)
        MacroDot(name: String(localized: "脂肪"), grams: recipe.fatG, color: AppColors.fat)
    }
}

/// 一种营养素：小圆点 + 「蛋白质 28 克」
private struct MacroDot: View {
    let name: String
    let grams: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(name) \(grams.noDecimal) 克")
                .font(AppTypography.detail)
                .monospacedDigit()
                .foregroundStyle(AppColors.textSecondary)
        }
        .fixedSize()
    }
}

/// 食谱卡片的最后一行：一个次要的「换一个」（换的时候显示「正在换…」）。
/// 打开做法不用单独的按钮：点卡片本身就行
struct RecipeCardFooter: View {
    let isSwapping: Bool
    let isBusy: Bool  // 正在生成或换别的：「换一个」不能点
    let onSwap: () -> Void

    var body: some View {
        HStack {
            Button(action: onSwap) {
                HStack(spacing: 6) {
                    if isSwapping {
                        AppLoadingIndicator()
                        Text("正在换…")
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("换一个")
                    }
                }
                .font(AppTypography.detail)
                .foregroundStyle(AppColors.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(isBusy)
            .opacity(isBusy && !isSwapping ? 0.5 : 1)
            .accessibilityHint("重新推荐这一餐")
            Spacer()
        }
    }
}

/// 还没有推荐：和其他「没有内容」一样的样子（碗 + 一句说明），下面是「生成一日三餐」（这时它是这一页唯一的主按钮）。
/// 生成中换成冒热气的碗和一句正在做什么（不显示假的百分比，也不说「通常要几秒」）
struct EmptyRecipesCard: View {
    let isGenerating: Bool
    let onGenerate: () -> Void

    var body: some View {
        Group {
            if isGenerating {
                BrandedStateView(
                    kind: .loading, title: String(localized: "正在生成今天的食谱"),
                    message: String(localized: "按你的目标搭配三餐…"), visualWidth: 72)
            } else {
                BrandedStateView(
                    kind: .empty, title: String(localized: "还没有今日推荐"),
                    message: String(localized: "按你的每日目标和饮食偏好，生成早餐、午餐和晚餐。"), visualWidth: 64
                ) {
                    Button(action: onGenerate) {
                        Label("生成一日三餐", systemImage: "sparkles")
                    }
                    .buttonStyle(.appPrimary)
                    .padding(.top, AppSpacing.xxs)
                }
            }
        }
        .padding(.vertical, AppSpacing.md)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.25), value: isGenerating)
    }
}

/// 已经有推荐时的「重新生成一日三餐」：次要按钮（燕麦色底、深橄榄字），比推荐的内容安静
struct RegenerateButton: View {
    let isGenerating: Bool
    let isBusy: Bool
    let onGenerate: () -> Void

    var body: some View {
        Button(action: onGenerate) {
            HStack(spacing: AppSpacing.xs) {
                if isGenerating {
                    AppLoadingIndicator()
                    Text("正在生成今天的食谱…")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("重新生成一日三餐")
                }
            }
        }
        .buttonStyle(.appSecondary)
        .disabled(isBusy && !isGenerating)
        .allowsHitTesting(!isBusy)
    }
}

/// 饮食偏好的摘要：第一行是偏好，下面一行是过敏、忌口和烹饪时间；右边一个小箭头（点了修改）
struct PreferenceSummary: View {
    let preferences: String
    let allergies: String
    let dislikes: String
    let cookingMinutes: Int

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(preferences.isEmpty ? String(localized: "未填写") : preferences)
                    .font(AppTypography.itemName)
                    .foregroundStyle(preferences.isEmpty ? AppColors.textSecondary : AppColors.textPrimary)
                    .lineLimit(2)
                Text(conditions)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AppSpacing.xs)
            AppChevron()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// 「过敏：花生、虾 · 忌口：香菜 · 每餐不超过 30 分钟」
    private var conditions: String {
        [
            String(localized: "过敏：\(allergies.isEmpty ? String(localized: "无") : allergies)"),
            String(localized: "忌口：\(dislikes.isEmpty ? String(localized: "无") : dislikes)"),
            String(localized: "每餐不超过 \(cookingMinutes) 分钟"),
        ].joined(separator: " · ")
    }
}
