//
//  RecipesView.swift
//  FoodTracker
//
//  「食谱」页：按每日目标和偏好生成一日三餐，每一餐一张卡片，可以点开看详情，也可以单独「换一个」。
//

import SwiftData
import SwiftUI

struct RecipesView: View {
    let profile: UserProfile

    // 偏好（和设置页读同一份本地数据）
    @AppStorage(RecipePrefKeys.preferences) private var preferencesText = ""
    @AppStorage(RecipePrefKeys.allergies) private var allergiesText = ""
    @AppStorage(RecipePrefKeys.dislikes) private var dislikesText = ""
    @AppStorage(RecipePrefKeys.cookingMinutes) private var cookingMinutes = 30
    // 上次生成的食谱，存起来下次打开还能看到
    @AppStorage(RecipePrefKeys.lastPlan) private var lastPlanData = Data()

    @State private var recipes: [Recipe] = []
    @State private var isGeneratingAll = false  // 正在生成整套
    @State private var swappingMeal: MealSlot?  // 正在「换一个」的那一餐
    @State private var remaining: Int?  // 今天还能生成几次
    @State private var showPreferences = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var isBusy: Bool { isGeneratingAll || swappingMeal != nil }

    var body: some View {
        NavigationStack {
            List {
                targetsSection
                preferencesSection
                generateSection
                ForEach(recipes) { recipe in
                    mealSection(recipe)
                }
            }
            .navigationTitle("食谱")
            .sheet(isPresented: $showPreferences) {
                RecipePreferencesView()
            }
            .alert("生成失败", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            // 固定在页面最底部的提示
            .safeAreaInset(edge: .bottom) {
                Text("食谱与营养数据为 AI 估算，仅供参考；如有疾病、处于孕期或有特殊饮食需求，请咨询医生或营养师")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
            .task {
                loadLastPlan()
                await refreshQuota()
            }
        }
    }

    // MARK: - 页面的各个部分

    /// 今天的目标：食谱就是按这个生成的
    private var targetsSection: some View {
        let t = profile.targets
        return Section("按你的每日目标推荐") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(t.calories.noDecimal)
                    .font(.title2.bold())
                Text("千卡")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("蛋白质 \(t.proteinG.noDecimal) · 碳水 \(t.carbsG.noDecimal) · 脂肪 \(t.fatG.noDecimal) 克")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("目标：\(profile.bodyInfo.goal.title) · 三餐按 30% / 40% / 30% 分配")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 偏好和忌口的摘要，点进去修改
    private var preferencesSection: some View {
        Section("偏好和忌口") {
            Button {
                showPreferences = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    summaryRow("偏好", preferencesText.isEmpty ? "未填写" : preferencesText)
                    summaryRow("过敏", allergiesText.isEmpty ? "无" : allergiesText)
                    summaryRow("忌口", dislikesText.isEmpty ? "无" : dislikesText)
                    summaryRow("烹饪时间", "每餐不超过 \(cookingMinutes) 分钟")
                }
            }
            .foregroundStyle(.primary)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .lineLimit(2)
            Spacer()
        }
        .font(.subheadline)
    }

    /// 生成按钮和剩余次数
    private var generateSection: some View {
        Section {
            Button {
                Task { await generateAll() }
            } label: {
                HStack {
                    if isGeneratingAll {
                        ProgressView()
                        Text("正在生成，通常需要 10～20 秒…")
                    } else {
                        Label(recipes.isEmpty ? "生成一日三餐" : "重新生成一日三餐", systemImage: "sparkles")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isBusy)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            if let remaining {
                Text("今天还可以生成 \(remaining) 次（含「换一个」）。短时间内用相同的条件重新生成，会直接使用上次的结果，不占次数。")
            }
        }
    }

    /// 一餐一张卡片：点卡片看详情，点「换一个」重新生成这一餐
    private func mealSection(_ recipe: Recipe) -> some View {
        Section {
            NavigationLink {
                RecipeDetailView(recipe: recipe)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.name)
                        .font(.headline)
                    Text("\(recipe.caloriesKcal.noDecimal) 千卡 · 蛋白质 \(recipe.proteinG.oneDecimal) · 碳水 \(recipe.carbsG.oneDecimal) · 脂肪 \(recipe.fatG.oneDecimal) 克")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("约 \(recipe.cookingMinutes) 分钟 · \(recipe.ingredients.count) 种食材")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Button {
                Task { await swap(recipe.meal) }
            } label: {
                HStack {
                    if swappingMeal == recipe.meal {
                        ProgressView()
                        Text("正在换…")
                    } else {
                        Label("换一个", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .disabled(isBusy)
        } header: {
            Label(recipe.meal.title, systemImage: recipe.meal.systemImage)
        }
    }

    // MARK: - 功能

    /// 组装发给后端的请求
    private func makeRequest(meals: [MealSlot], excludeNames: [String]) -> RecipeRequest {
        let t = profile.targets
        return RecipeRequest(
            goal: profile.bodyInfo.goal.rawValue,
            dailyCalories: t.calories,
            dailyProteinG: t.proteinG,
            dailyCarbsG: t.carbsG,
            dailyFatG: t.fatG,
            preferences: preferencesText.trimmingCharacters(in: .whitespacesAndNewlines),
            allergies: allergiesText.asTermList,
            dislikes: dislikesText.asTermList,
            maxCookingMinutes: cookingMinutes,
            meals: meals,
            excludeNames: excludeNames,
            lang: "zh"  // 界面目前只有中文；以后做英文版时再跟随手机语言
        )
    }

    /// 生成整套三餐
    private func generateAll() async {
        isGeneratingAll = true
        defer { isGeneratingAll = false }
        do {
            let result = try await APIClient.recipes(makeRequest(meals: MealSlot.allCases, excludeNames: []))
            recipes = result.recipes
            remaining = result.remainingToday
            saveLastPlan()
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// 只换某一餐：把现在的菜名都告诉后端，让它避开
    private func swap(_ meal: MealSlot) async {
        swappingMeal = meal
        defer { swappingMeal = nil }
        do {
            let result = try await APIClient.recipes(makeRequest(meals: [meal], excludeNames: recipes.map(\.name)))
            if let replacement = result.recipes.first(where: { $0.meal == meal }),
                let index = recipes.firstIndex(where: { $0.meal == meal })
            {
                recipes[index] = replacement
            }
            remaining = result.remainingToday
            saveLastPlan()
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// 问后端今天还剩几次；失败就不显示，不打扰用户
    private func refreshQuota() async {
        if let quota = try? await APIClient.quota() {
            remaining = quota.recipesRemaining
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }

    // 上次的食谱存成 JSON 放在本地，下次打开直接显示
    private func saveLastPlan() {
        lastPlanData = (try? JSONEncoder().encode(recipes)) ?? Data()
    }

    private func loadLastPlan() {
        guard recipes.isEmpty, !lastPlanData.isEmpty,
            let saved = try? JSONDecoder().decode([Recipe].self, from: lastPlanData)
        else { return }
        recipes = saved
    }
}

#Preview {
    RecipesView(
        profile: UserProfile(
            body: BodyInfo(sex: .female, age: 28, heightCm: 165, weightKg: 60, activity: .light, goal: .loseFat))
    )
    .modelContainer(for: AppModels.all, inMemory: true)
}
