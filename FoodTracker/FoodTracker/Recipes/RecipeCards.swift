//
//  RecipeCards.swift
//  FoodTracker
//
//  「食谱」页用到的几种卡片：
//  - RecipeGoalSummary：每日目标的摘要（辅助信息：小一号的燕麦色卡片，放在推荐下面）
//  - RecipeCard + RecipeCardFooter：一餐的推荐（餐次标签、菜名、热量、三大营养素、时间；下面一行是「查看做法」「换一个」）
//  - EmptyRecipesCard：还没有推荐时的样子，里面是「生成一日三餐」
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
        .background(AppColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppRadius.compact, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var macroItems: some View {
        MacroDot(name: String(localized: "蛋白质"), grams: targets.proteinG, color: AppColors.protein)
        MacroDot(name: String(localized: "碳水"), grams: targets.carbsG, color: AppColors.carbs)
        MacroDot(name: String(localized: "脂肪"), grams: targets.fatG, color: AppColors.fat)
    }
}

/// 餐次的小标签：图标 + 早餐 / 午餐 / 晚餐，底色是很淡的燕麦、鼠尾草、灰褐
struct MealSlotTag: View {
    let slot: MealSlot

    private var tint: Color {
        switch slot {
        case .breakfast: AppColors.tintBreakfast
        case .lunch: AppColors.tintLunch
        case .dinner: AppColors.tintDinner
        }
    }

    var body: some View {
        Label(slot.title, systemImage: slot.systemImage)
            .font(AppTypography.caption.weight(.medium))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint, in: RoundedRectangle(cornerRadius: AppRadius.tag, style: .continuous))
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
            Text(recipe.name)
                .font(AppTypography.recipeName)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
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

/// 食谱卡片的最后一行：左边「查看做法」是主要动作（浅橄榄色的胶囊），右边「换一个」是次要动作（只有图标和灰字）
struct RecipeCardFooter: View {
    let isSwapping: Bool
    let isBusy: Bool  // 正在生成或换别的：「换一个」不能点
    let onOpen: () -> Void
    let onSwap: () -> Void

    var body: some View {
        HStack {
            Button(action: onOpen) {
                HStack(spacing: AppSpacing.xxs) {
                    Text("查看做法")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(AppTypography.detail.weight(.semibold))
                .foregroundStyle(AppColors.brandDeep)
                .padding(.horizontal, AppSpacing.md - 2)
                .frame(minHeight: 34)
                .background(AppColors.brandSoft, in: Capsule())
                .frame(minHeight: 44)  // 能点的范围有 44pt 高
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            Spacer(minLength: AppSpacing.sm)

            Button(action: onSwap) {
                HStack(spacing: 6) {
                    if isSwapping {
                        ProgressView()
                            .controlSize(.small)
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
        }
    }
}

/// 还没有推荐：碗的图案 + 一句说明 + 「生成一日三餐」（这时它是这一页唯一的主按钮）
struct EmptyRecipesCard: View {
    let isGenerating: Bool
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            KindbiteMark()
                .frame(width: 64)
                .opacity(0.9)
                .padding(.top, AppSpacing.xs)
            VStack(spacing: 6) {
                Text("还没有今日推荐")
                    .font(AppTypography.mealTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("按你的每日目标和饮食偏好，生成早餐、午餐和晚餐。")
                    .font(AppTypography.detail)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onGenerate) {
                GenerateLabel(isGenerating: isGenerating, title: "生成一日三餐")
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(AppColors.brand, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            }
            .buttonStyle(AppPressStyle())
            .disabled(isGenerating)
        }
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity)
    }
}

/// 已经有推荐时的「重新生成一日三餐」：橄榄绿、46pt 高、圆角 18 的按钮，放在推荐卡片下面，比推荐内容低一级
struct RegenerateButton: View {
    let isGenerating: Bool
    let isBusy: Bool
    let onGenerate: () -> Void

    var body: some View {
        Button(action: onGenerate) {
            GenerateLabel(isGenerating: isGenerating, title: "重新生成一日三餐")
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(AppColors.brand, in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
        }
        .buttonStyle(AppPressStyle())
        .disabled(isBusy)
        .opacity(isBusy && !isGenerating ? 0.5 : 1)
    }
}

/// 生成按钮上的字：平时是「✦ 生成…」，生成中是转圈 + 「正在生成…」
private struct GenerateLabel: View {
    let isGenerating: Bool
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if isGenerating {
                ProgressView()
                    .tint(AppColors.onBrand)
                Text("正在生成，通常需要 10～20 秒…")
            } else {
                Image(systemName: "sparkles")
                Text(title)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppColors.onBrand)
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
