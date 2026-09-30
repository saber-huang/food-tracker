//
//  RecipeDetailView.swift
//  FoodTracker
//
//  食谱详情：营养数据、食材和克数、做法步骤。
//

import SwiftUI

struct RecipeDetailView: View {
    let recipe: Recipe

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
                        NutrientColumn(name: "蛋白质", grams: recipe.proteinG, color: .blue)
                        NutrientColumn(name: "碳水", grams: recipe.carbsG, color: .orange)
                        NutrientColumn(name: "脂肪", grams: recipe.fatG, color: .pink)
                    }
                }
                .padding(.vertical, 4)
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
}

#Preview {
    NavigationStack {
        RecipeDetailView(
            recipe: Recipe(
                meal: .lunch, name: "清蒸鸡胸肉配西兰花糙米饭",
                ingredients: [
                    Ingredient(name: "鸡胸肉", grams: 170), Ingredient(name: "糙米", grams: 45),
                    Ingredient(name: "西兰花", grams: 150), Ingredient(name: "橄榄油", grams: 8),
                ],
                steps: ["糙米提前浸泡后蒸熟。", "鸡胸肉切片，用生抽腌 5 分钟后蒸 12 分钟。", "西兰花焯水后快炒 1 分钟。", "装盘即可。"],
                cookingMinutes: 30, caloriesKcal: 590, proteinG: 48, carbsG: 63, fatG: 16
            ))
    }
}
