//
//  RecipesView.swift
//  FoodTracker
//
//  「食谱」页，从上到下：
//  1. 每日目标的摘要（食谱就是按它生成的）
//  2. 今日推荐：早餐、午餐、晚餐各一张卡片（点卡片或「查看做法」看详情，「换一个」单独重新生成这一餐）；
//     还没有推荐时是一张带「生成一日三餐」的卡片。下面是不太大的「重新生成一日三餐」和剩余次数
//  3. 饮食偏好的摘要（点了修改）；最下面固定一行 AI 估算的提示
//  卡片的样子在 RecipeCards.swift。
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
    @State private var pendingAIAction: PendingAIAction?  // 还没同意使用 AI 时，先记下要做的生成，同意后再做
    @State private var showPreferences = false
    @State private var openedRecipe: Recipe?  // 有值时打开这道菜的详情
    @State private var showError = false
    @State private var errorMessage = ""

    private var isBusy: Bool { isGeneratingAll || swappingMeal != nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RecipeGoalSummary(targets: profile.targets, goalTitle: profile.bodyInfo.goal.title)
                        .appCardRow()
                } header: {
                    Text("按你的每日目标推荐")
                        .font(AppTypography.detail)
                        .foregroundStyle(AppColors.textSecondary)
                        .textCase(nil)
                }

                if recipes.isEmpty {
                    Section {
                        EmptyRecipesCard(isGenerating: isGeneratingAll) { generateTapped() }
                            .appCardRow()
                    } header: {
                        AppSectionHeader(title: String(localized: "今日推荐"))
                    } footer: {
                        remainingCaption
                    }
                } else {
                    ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                        recipeSection(recipe, showsHeader: index == 0)
                    }
                    Section {
                        VStack(spacing: AppSpacing.xs) {
                            RegenerateButton(isGenerating: isGeneratingAll, isBusy: isBusy) { generateTapped() }
                            remainingCaption
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: AppSpacing.xxs, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }

                // 饮食偏好：设置条件，放在推荐下面，比推荐安静
                Section {
                    Button {
                        showPreferences = true
                    } label: {
                        PreferenceSummary(
                            preferences: preferencesText, allergies: allergiesText, dislikes: dislikesText,
                            cookingMinutes: cookingMinutes)
                    }
                    .buttonStyle(AppPressStyle(scales: false))
                    .appCardRow()
                } header: {
                    AppSectionHeaderWithAction(title: String(localized: "饮食偏好"), actionTitle: String(localized: "编辑")) {
                        showPreferences = true
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(AppSpacing.cardGap)
            .contentMargins(.horizontal, AppSpacing.pageMargin, for: .scrollContent)
            .appListBackground()  // 页面用 App 的暖色背景（和「今日」页一样）
            .navigationTitle("食谱")
            .navigationDestination(item: $openedRecipe) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            #if DEBUG && targetEnvironment(simulator)
            // 只在模拟器里出现的调试菜单：不花钱就能看食谱卡片的样子
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("调试") {
                        Button("用示例食谱") { recipes = SampleData.recipePlan }
                        Button("清空食谱") { recipes = [] }
                    }
                }
            }
            #endif
            .sheet(isPresented: $showPreferences) {
                RecipePreferencesView()
            }
            // 第一次生成前：说明会发送什么、发给谁，同意后才发送（见 AIConsent.swift）
            .aiConsentSheet(pending: $pendingAIAction)
            .alert("生成失败", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            // 固定在页面最底部的提示
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
            .task {
                loadLastPlan()
                await refreshQuota()
            }
        }
    }

    // MARK: - 页面的各个部分

    /// 一餐一张卡片：点卡片或「查看做法」看详情，点「换一个」重新生成这一餐
    private func recipeSection(_ recipe: Recipe, showsHeader: Bool) -> some View {
        Section {
            Button {
                openedRecipe = recipe
            } label: {
                RecipeCard(recipe: recipe)
            }
            .buttonStyle(AppPressStyle(scales: false))
            .listRowSeparator(.hidden)
            .appCardRow()

            RecipeCardFooter(
                isSwapping: swappingMeal == recipe.meal, isBusy: isBusy, onOpen: { openedRecipe = recipe },
                onSwap: { AIConsent.perform(pending: $pendingAIAction) { Task { await swap(recipe.meal) } } }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.cardPadding, bottom: 0, trailing: AppSpacing.cardPadding))
            .appCardRow()
        } header: {
            if showsHeader {
                AppSectionHeader(title: String(localized: "今日推荐"))
            }
        }
    }

    /// 今天还能生成几次（含「换一个」）：小字，不抢推荐的风头；问不到就不显示
    @ViewBuilder
    private var remainingCaption: some View {
        if let remaining {
            Text("今天还可以生成 \(remaining) 次（含「换一个」）。短时间内用相同的条件重新生成，会直接使用上次的结果，不占次数。")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    /// 点了生成：没同意过使用 AI 时，先弹出说明；同意后才发送目标和偏好
    private func generateTapped() {
        AIConsent.perform(pending: $pendingAIAction) { Task { await generateAll() } }
    }

    // MARK: - 功能

    /// 组装发给后端的请求：按用户的每日目标（和「推荐下一餐」共用同一个组装函数）
    private func makeRequest(meals: [MealSlot], excludeNames: [String]) -> RecipeRequest {
        RecipeRequest.make(
            goal: profile.bodyInfo.goal, targets: RequestTargets(profile.targets), preferencesText: preferencesText,
            allergiesText: allergiesText, dislikesText: dislikesText, cookingMinutes: cookingMinutes, meals: meals,
            excludeNames: excludeNames)
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

/// 「食谱」页、食谱详情和「推荐下一餐」共用的文字
enum RecipeCopy {
    static let disclaimer = String(localized: "食谱与营养数据为 AI 估算，仅供参考；如有疾病、处于孕期或有特殊饮食需求，请咨询医生或营养师")
}

/// 一道菜的摘要：菜名、热量和营养素、时间和食材数（「食谱」页和「推荐下一餐」的卡片共用）
struct RecipeSummaryLabel: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipe.name)
                .font(.headline)
            Text(
                "\(recipe.caloriesKcal.noDecimal) 千卡 · 蛋白质 \(recipe.proteinG.oneDecimal) · 碳水 \(recipe.carbsG.oneDecimal) · 脂肪 \(recipe.fatG.oneDecimal) 克"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("约 \(recipe.cookingMinutes) 分钟 · \(recipe.ingredients.count) 种食材")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    RecipesView(
        profile: UserProfile(
            body: BodyInfo(sex: .female, age: 28, heightCm: 165, weightKg: 60, activity: .light, goal: .loseFat))
    )
    .modelContainer(for: AppModels.all, inMemory: true)
}
