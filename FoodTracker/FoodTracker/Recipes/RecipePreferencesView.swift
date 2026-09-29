//
//  RecipePreferencesView.swift
//  FoodTracker
//
//  食谱偏好设置：饮食偏好、过敏食材、忌口、可接受的烹饪时间。
//  用 @AppStorage 存在手机本地（UserDefaults），改了立刻保存，下次自动带入。
//

import SwiftUI

/// 偏好在本地存储里用的名字。食谱页和设置页都用这几个名字读同一份数据
enum RecipePrefKeys {
    static let preferences = "recipePreferences"
    static let allergies = "recipeAllergies"
    static let dislikes = "recipeDislikes"
    static let cookingMinutes = "recipeCookingMinutes"
    static let lastPlan = "recipeLastPlan"
}

extension String {
    /// 把「花生、虾, 牛奶」这样的文字拆成 ["花生", "虾", "牛奶"]：支持顿号、逗号、分号和换行
    var asTermList: [String] {
        split(whereSeparator: { "、,，;；\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct RecipePreferencesView: View {
    @AppStorage(RecipePrefKeys.preferences) private var preferencesText = ""
    @AppStorage(RecipePrefKeys.allergies) private var allergiesText = ""
    @AppStorage(RecipePrefKeys.dislikes) private var dislikesText = ""
    @AppStorage(RecipePrefKeys.cookingMinutes) private var cookingMinutes = 30

    @Environment(\.dismiss) private var dismiss

    private let cookingOptions = [15, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：清淡少油，早餐想吃中式，喜欢吃辣", text: $preferencesText, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("饮食偏好（可不填）")
                } footer: {
                    Text("用一两句话描述就行，AI 会参考。")
                }

                Section {
                    TextField("例如：花生、虾", text: $allergiesText, axis: .vertical)
                } header: {
                    Text("过敏食材")
                } footer: {
                    Text("多个食材用顿号或逗号分开。食谱里绝对不会出现这些食材和它们制成的食品。")
                }

                Section {
                    TextField("例如：香菜、动物内脏", text: $dislikesText, axis: .vertical)
                } header: {
                    Text("忌口")
                } footer: {
                    Text("不想吃的食材，同样不会出现在食谱里。")
                }

                Section("每餐可接受的烹饪时间") {
                    Picker("烹饪时间", selection: $cookingMinutes) {
                        ForEach(cookingOptions, id: \.self) { minutes in
                            Text("\(minutes) 分钟").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("偏好和忌口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    RecipePreferencesView()
}
