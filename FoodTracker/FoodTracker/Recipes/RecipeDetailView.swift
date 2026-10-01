//
//  RecipeDetailView.swift
//  FoodTracker
//
//  食谱详情：像一页菜谱，而不是数据表。从上到下：
//  1. 「晚餐 · 约 28 分钟」和菜名（大标题写在页面里；顶栏只留返回，长菜名不挤在顶栏里）
//  2. 一张卡片：热量（旁边「AI 估算 ⓘ」）和三大营养素
//  3. 食材：标题行「食材 …… 份量（生重）」（右边那个小标题很淡），下面一张卡片，每行一种食材，克数右对齐
//  4. 做法：每一步是一小段——先是编号小圆圈，下面是这一步的文字（行距放宽）；步骤之间靠留白分开，不像列表
//  最下面固定着「＋ 记录这餐」（跟着安全区，滚动时一直看得见；内容滚到底时最后一步不会被它挡住）：
//  把整道菜记成今天的一条饮食记录（份量 = 食材生重合计），记到哪一餐由用户选，记好后轻轻震一下。
//  这是二级页面：底部的标签栏藏起来。
//

import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe

    @Environment(\.modelContext) private var modelContext
    @State private var showMealChoice = false  // 是否弹出「记到哪一餐？」
    @State private var logged: MealType?  // 这次打开后记到了哪一餐；记过就不能再点，防止连点记成两条
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 34

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                header
                nutritionCard
                ingredientsSection
                stepsSection
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.xxl)
        }
        .background { AppBackground(glow: false) }
        .navigationBarTitleDisplayMode(.inline)
        .hidesFloatingTabBar()
        .safeAreaInset(edge: .bottom) { logButton }
    }

    // MARK: - 页面的几块

    /// 「晚餐 · 约 28 分钟」+ 菜名
    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: recipe.meal.systemImage)
                    .accessibilityHidden(true)
                Text(recipe.meal.title) + Text(verbatim: " · ") + Text("约 \(recipe.cookingMinutes) 分钟")
            }
            .font(AppTypography.detail.weight(.medium))
            .foregroundStyle(AppColors.textSecondary)

            Text(recipe.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// 热量和三大营养素
    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                    Text(recipe.caloriesKcal.noDecimal)
                        .font(AppTypography.heroNumber(size: numberSize))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textPrimary)
                    Text("千卡")
                        .font(AppTypography.heroCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: AppSpacing.xs)
                AIEstimateBadge()
            }
            MacroStatsRow(proteinG: recipe.proteinG, carbsG: recipe.carbsG, fatG: recipe.fatG)
        }
        .padding(AppSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    /// 食材：一张卡片，每行一种，右边是克数；分隔线只从文字开始，很淡
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // 标题行像一张表的表头：左边「食材」，右边很淡的「份量（生重）」，正好在克数那一列上面
            HStack(alignment: .firstTextBaseline) {
                Text("食材")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("份量（生重）")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.leading, AppSpacing.xxs)
            .padding(.trailing, AppSpacing.cardPadding)

            VStack(spacing: 0) {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                    if index > 0 {
                        Rectangle()
                            .fill(AppColors.divider)
                            .frame(height: 1)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(ingredient.name)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer(minLength: AppSpacing.sm)
                        Text("\(ingredient.grams.noDecimal) 克")
                            .monospacedDigit()
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .font(.body)
                    .frame(minHeight: 54)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .appCard()
        }
    }

    /// 做法：每一步先是编号小圆圈，下面是这一步的文字（行距放宽）；步骤之间靠留白分开，不画线、不做成列表
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Text("做法")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                RecipeStepView(number: index + 1, text: step)
            }
        }
        .padding(.horizontal, AppSpacing.xxs)
    }

    /// 最下面的「＋ 记录这餐」；记过之后变成「✓ 已记录到午餐」，不能再点
    private var logButton: some View {
        Button {
            showMealChoice = true
        } label: {
            Label(
                logged.map { String(localized: "已记录到\($0.title)") } ?? String(localized: "记录这餐"),
                systemImage: logged == nil ? "plus" : "checkmark"
            )
        }
        // 记过之后换成次要按钮的样子（不是变灰），表示已经完成；不能再点，防止记成两条
        .buttonStyle(AppButtonStyle(kind: logged == nil ? .primary : .secondary))
        .allowsHitTesting(logged == nil)
        .sensoryFeedback(.success, trigger: logged)
        // 选记到哪一餐：这道菜本来是哪一餐，就在那一项后面标「（推荐）」
        .confirmationDialog("记到哪一餐？", isPresented: $showMealChoice, titleVisibility: .visible) {
            ForEach(MealType.allCases) { meal in
                Button(meal == MealType(slot: recipe.meal) ? String(localized: "\(meal.title)（推荐）") : meal.title) {
                    log(meal)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .padding(.horizontal, AppSpacing.pageMargin)
        .padding(.vertical, AppSpacing.xs)
        .appBottomBar()
    }

    /// 记成今天的一条记录：整道菜一条，份量是食材生重合计（之后可以在「今日」里改份量）
    private func log(_ meal: MealType) {
        // 按钮变灰要等下一次刷新界面，所以这里再检查一次，连点两下也只记一条
        guard logged == nil else { return }
        modelContext.insert(
            FoodEntry(
                dayKey: DayMath.dayKey(for: .now), meal: meal, name: recipe.name, weightG: DietLogMath.weight(of: recipe),
                values: DietLogMath.rounded(NutrientValues(recipe: recipe)), source: .recipe))
        try? modelContext.save()
        logged = meal
    }
}

/// 做法里的一步：24pt 的编号小圆圈，下面是这一步的文字
private struct RecipeStepView: View {
    let number: Int
    let text: String

    @ScaledMetric(relativeTo: .subheadline) private var badgeSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(verbatim: "\(number)")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppColors.brandDeep)
                .frame(width: badgeSize, height: badgeSize)
                .background(AppColors.brandSoft, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .foregroundStyle(AppColors.textPrimary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("第 \(number) 步：") + Text(text))
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: SampleData.recipe)
    }
    .modelContainer(for: AppModels.all, inMemory: true)
}
