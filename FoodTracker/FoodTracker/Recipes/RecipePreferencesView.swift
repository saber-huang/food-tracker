//
//  RecipePreferencesView.swift
//  FoodTracker
//
//  食谱偏好设置：饮食偏好、过敏食材、忌口、可接受的烹饪时间。和其他表单页同一套样子（AppForm）：
//  顶栏「取消 / 偏好和忌口 / 保存」，先改一份草稿，点「保存」才存进手机本地（UserDefaults）。
//  过敏食材怎么写、会怎么用，放在标题旁的 ⓘ 里（不承诺「绝对不会出现」：推荐会尽量避开，AI 仍可能有疏漏）。
//

import SwiftUI

/// 偏好在本地存储里用的名字。食谱页和设置页都用这几个名字读同一份数据
nonisolated enum RecipePrefKeys {
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
    @AppStorage(RecipePrefKeys.preferences) private var savedPreferences = ""
    @AppStorage(RecipePrefKeys.allergies) private var savedAllergies = ""
    @AppStorage(RecipePrefKeys.dislikes) private var savedDislikes = ""
    @AppStorage(RecipePrefKeys.cookingMinutes) private var savedCookingMinutes = 30

    @Environment(\.dismiss) private var dismiss
    // 先改一份草稿：点「保存」才存下来，点「取消」什么都不变
    @State private var preferences = ""
    @State private var allergies = ""
    @State private var dislikes = ""
    @State private var cookingMinutes = 30
    @State private var didLoad = false
    @State private var savedTick = 0  // 保存时加 1：轻轻震一下

    static let cookingOptions = [15, 30, 45, 60, 90]

    var body: some View {
        AppForm {
            AppFormSection(String(localized: "饮食偏好（可选）")) {
                AppFormTextField(
                    title: String(localized: "饮食偏好"), placeholder: String(localized: "例如：清淡少油，早餐想吃中式，喜欢吃辣"),
                    text: $preferences, multiline: true)
            }
            // 过敏食材怎么写、会怎么用，放在 ⓘ 里，不长期挂在页面上
            AppFormSection(title: String(localized: "过敏食材"), accessory: { InfoButton(topic: .allergies) }) {
                AppFormTextField(title: String(localized: "过敏食材"), placeholder: String(localized: "例如：花生、虾"), text: $allergies)
            }
            AppFormSection(String(localized: "忌口")) {
                AppFormTextField(title: String(localized: "忌口"), placeholder: String(localized: "例如：香菜、动物内脏"), text: $dislikes)
            }
            // 格子里只写数字，单位「分钟」写在标题里（写一次）；旁白读「30 分钟」
            AppFormSection(String(localized: "每餐可接受的烹饪时间（分钟）")) {
                AppSegmentedControl(
                    title: String(localized: "每餐可接受的烹饪时间"), selection: $cookingMinutes, options: Self.cookingOptions,
                    label: { "\($0)" }, accessibilityLabel: { String(localized: "\($0) 分钟") }
                )
                .padding(AppSpacing.sm)
            }
        }
        .appSheetHeader(
            AppSheetHeader(
                title: String(localized: "偏好和忌口"), onCancel: { dismiss() }, confirmTitle: String(localized: "保存"),
                onConfirm: save))
        .sensoryFeedback(.success, trigger: savedTick)
        .onAppear(perform: load)
        .appSheet()
    }

    /// 打开时把存着的偏好放进草稿（只做一次：从别的页面回来不会把正在改的内容冲掉）
    private func load() {
        guard !didLoad else { return }
        didLoad = true
        preferences = savedPreferences
        allergies = savedAllergies
        dislikes = savedDislikes
        cookingMinutes = Self.cookingOptions.contains(savedCookingMinutes) ? savedCookingMinutes : 30
    }

    /// 保存：存下来，轻轻震一下，关掉这一页（不弹「保存成功」）
    private func save() {
        savedPreferences = preferences.trimmingCharacters(in: .whitespacesAndNewlines)
        savedAllergies = allergies.trimmingCharacters(in: .whitespacesAndNewlines)
        savedDislikes = dislikes.trimmingCharacters(in: .whitespacesAndNewlines)
        savedCookingMinutes = cookingMinutes
        savedTick += 1
        dismiss()
    }
}

#Preview {
    RecipePreferencesView()
}
