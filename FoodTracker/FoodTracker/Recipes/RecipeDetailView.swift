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

    var body: some View {
        List {
            Section {
                HStack {
                    Label(recipe.meal.title, systemImage: recipe.meal.systemImage)
                    Spacer()
                    Label("约 \(recipe.cookingMinutes) 分钟", systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(recipe.caloriesKcal.noDecimal)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("千卡")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        NutrientColumn(name: String(localized: "蛋白质"), value: recipe.proteinG.noDecimal, color: Theme.protein)
                        NutrientColumn(name: String(localized: "碳水"), value: recipe.carbsG.noDecimal, color: Theme.carbs)
                        NutrientColumn(name: String(localized: "脂肪"), value: recipe.fatG.noDecimal, color: Theme.fat)
                    }
                }
                .padding(.vertical, 4)

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

            Section("食材（生重）") {
                ForEach(recipe.ingredients, id: \.self) { ingredient in
                    HStack {
                        Text(ingredient.name)
                        Spacer()
                        Text("\(ingredient.grams.noDecimal) 克")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("做法") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.tint)
                            .frame(width: 20, alignment: .trailing)
                        Text(step)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text(RecipeCopy.disclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.bar)
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
