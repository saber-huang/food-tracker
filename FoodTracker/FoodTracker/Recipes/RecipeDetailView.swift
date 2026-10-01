//
//  RecipeDetailView.swift
//  FoodTracker
//
//  食谱详情：营养数据、「记录到今日」、食材和克数、做法步骤。
//  「记录到今日」把整道菜记成今天的一条饮食记录（重量 = 食材生重合计），记到哪一餐由用户选。
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
        List {
            Group {
                Section {
                    // 和「食谱」页的卡片同一种样子：餐次标签和时间、大号的热量、三大营养素
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        HStack(alignment: .center) {
                            MealSlotTag(slot: recipe.meal)
                            Spacer(minLength: AppSpacing.xs)
                            Label("约 \(recipe.cookingMinutes) 分钟", systemImage: "clock")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
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
                        MacroStatsRow(proteinG: recipe.proteinG, carbsG: recipe.carbsG, fatG: recipe.fatG)
                    }
                    .padding(.vertical, AppSpacing.xs)

                    // 把这道菜记成今天的一餐
                    Button {
                        showMealChoice = true
                    } label: {
                        Label(
                            logged.map { String(localized: "已记录到\($0.title)") } ?? String(localized: "记录到今日"),
                            systemImage: logged == nil ? "plus.circle" : "checkmark.circle")
                    }
                    .disabled(logged != nil)
                    // 选记到哪一餐（挂在按钮上，弹出的小窗会指向这个按钮）：这道菜本来是哪一餐，就在那一项后面标「（推荐）」
                    .confirmationDialog("记到哪一餐？", isPresented: $showMealChoice, titleVisibility: .visible) {
                        ForEach(MealType.allCases) { meal in
                            Button(meal == MealType(slot: recipe.meal) ? String(localized: "\(meal.title)（推荐）") : meal.title) {
                                log(meal)
                            }
                        }
                        Button("取消", role: .cancel) {}
                    }
                }

                Section {
                    ForEach(recipe.ingredients, id: \.self) { ingredient in
                        HStack {
                            Text(ingredient.name)
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text("\(ingredient.grams.noDecimal) 克")
                                .monospacedDigit()
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                } header: {
                    AppSectionHeader(title: String(localized: "食材（生重）"))
                }

                Section {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            Text("\(index + 1)")
                                .font(AppTypography.number)
                                .foregroundStyle(AppColors.brand)
                                .frame(width: 20, alignment: .trailing)
                            Text(step)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    AppSectionHeader(title: String(localized: "做法"))
                }
            }
            .appCardRow()  // 卡片用暖白，分隔线很淡
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(AppSpacing.cardGap)
        .contentMargins(.horizontal, AppSpacing.pageMargin, for: .scrollContent)
        .appListBackground()  // 和「食谱」页同一种背景
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text(RecipeCopy.disclaimer)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.vertical, AppSpacing.xs)
                .frame(maxWidth: .infinity)
                .appBottomBar()
        }
    }

    /// 记成今天的一条记录：整道菜一条，重量是食材生重合计（之后可以在「今日」里改份量）
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

#Preview {
    NavigationStack {
        RecipeDetailView(recipe: SampleData.recipe)
    }
    .modelContainer(for: AppModels.all, inMemory: true)
}
