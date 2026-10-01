//
//  RecipesView.swift
//  FoodTracker
//
//  「食谱」页，从上到下（第一眼看到的是「今天推荐吃什么」）：
//  1. 页面标题「食谱」和一句说明（左对齐，和「我的」一样）
//  2. 今日推荐：早餐、午餐、晚餐各一张食谱卡片（点卡片或「查看做法」看详情，「换一个」单独重新生成这一餐）；
//     还没有推荐时是一张带「生成一日三餐」的卡片。下面是「重新生成一日三餐」和一行很小的剩余次数
//  3. 每日目标：小一号的辅助卡片（食谱就是按它生成的）
//  4. 饮食偏好的摘要（点了修改）；最下面一行很小的「营养数据为估算值，仅供参考。ⓘ」
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
    @State private var failure: RecipeFailure?  // 生成或「换一个」没成功：推荐上面出现一张出错卡片（可以重试）

    private var isBusy: Bool { isGeneratingAll || swappingMeal != nil }

    var body: some View {
        NavigationStack {
            List {
                // 页面标题：左对齐的「食谱」+ 一句说明（不用系统导航栏的标题，滚动时也不会变成居中的小标题）
                Section {
                    PageHeader(title: String(localized: "食谱"), subtitle: String(localized: "为你规划今天的一日三餐")) {
                        #if DEBUG && targetEnvironment(simulator)
                        // 只在模拟器里出现的调试菜单：不花钱就能看食谱卡片的样子
                        Menu {
                            Button("用示例食谱") { recipes = SampleData.recipePlan }
                            Button("清空食谱") { recipes = [] }
                        } label: {
                            Text("调试")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        #endif
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // 没生成成功：和其他出错一样的样子（没有热气的碗、一句能照着做的话、「重试」），
                // 不弹警告框，已有的推荐照常显示
                if let failure {
                    Section {
                        BrandedStateView(kind: .error, title: failure.title, message: failure.message, visualWidth: 56) {
                            Button("重试") { retry(failure) }
                                .buttonStyle(.appPrimary)
                            Button("关闭") { withAnimation(.easeOut(duration: 0.15)) { self.failure = nil } }
                                .buttonStyle(.appTertiary)
                        }
                        .padding(.vertical, AppSpacing.md)
                        .appCardRow()
                    }
                }

                // 今日推荐：这一页最重要的内容
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

                // 每日目标：辅助信息，小一号的燕麦色卡片
                Section {
                    RecipeGoalSummary(targets: profile.targets, goalTitle: profile.bodyInfo.goal.title)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    AppSectionHeader(title: String(localized: "每日目标"))
                }

                // 饮食偏好：设置条件，放在最后，比推荐安静
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
                } footer: {
                    // 整页只在最下面说一次「估算值」，点 ⓘ 看完整说明（不在每张卡片上重复）
                    AIFootnote()
                        .padding(.top, AppSpacing.sm)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(AppSpacing.cardGap)
            .contentMargins(.horizontal, AppSpacing.pageMargin, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
            .appListBackground()  // 页面用 App 的暖色背景（和「今日」页一样）
            .appStatusBarCover()  // 没有导航栏：状态栏那一条盖上背景色，内容滑上去时不和时间叠在一起
            .navigationTitle("食谱")  // 只用在详情页的「返回」上
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openedRecipe) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .sheet(isPresented: $showPreferences) {
                RecipePreferencesView()
            }
            // 第一次生成前：说明会发送什么、发给谁，同意后才发送（见 AIConsent.swift）
            .aiConsentSheet(pending: $pendingAIAction)
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
                    // 分隔线从卡片文字的左边开始；不写的话系统按第一段文字对齐，每张卡片的线长短不一样
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
            }
            .buttonStyle(AppPressStyle(scales: false))
            .listRowSeparator(.hidden, edges: .top)  // 卡片上边缘不要线
            .listRowSeparator(.visible, edges: .bottom)  // 卡片正文和下面的「换一个」之间一条很淡的线
            .appCardRow()

            RecipeCardFooter(
                isSwapping: swappingMeal == recipe.meal, isBusy: isBusy,
                onSwap: { AIConsent.perform(pending: $pendingAIAction) { Task { await swap(recipe.meal) } } }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.cardPadding - 4, bottom: 0, trailing: AppSpacing.cardPadding))
            .appCardRow()
        } header: {
            if showsHeader {
                AppSectionHeader(title: String(localized: "今日推荐"))
            }
        }
    }

    /// 今天还能生成几次（含「换一个」）：很小的浅色字，不抢推荐的风头；问不到就不显示
    @ViewBuilder
    private var remainingCaption: some View {
        if let remaining {
            Text("今天还可以生成 \(remaining) 次（含「换一个」）")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .textCase(nil)
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
        failure = nil
        defer { isGeneratingAll = false }
        do {
            let result = try await APIClient.recipes(makeRequest(meals: MealSlot.allCases, excludeNames: []))
            recipes = result.recipes
            remaining = result.remainingToday
            saveLastPlan()
        } catch {
            failure = RecipeFailure(retry: .all, message: error.localizedDescription)
        }
    }

    /// 只换某一餐：把现在的菜名都告诉后端，让它避开
    private func swap(_ meal: MealSlot) async {
        swappingMeal = meal
        failure = nil
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
            failure = RecipeFailure(retry: .swap(meal), message: error.localizedDescription)
        }
    }

    /// 出错卡片上的「重试」：上次做的是什么就再做一次
    private func retry(_ failure: RecipeFailure) {
        switch failure.retry {
        case .all: generateTapped()
        case .swap(let meal): AIConsent.perform(pending: $pendingAIAction) { Task { await swap(meal) } }
        }
    }

    /// 问后端今天还剩几次；失败就不显示，不打扰用户
    private func refreshQuota() async {
        if let quota = try? await APIClient.quota() {
            remaining = quota.recipesRemaining
        }
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

/// 生成或「换一个」没成功：说明 + 上次做的是什么（「重试」时再做一次）
private struct RecipeFailure: Equatable {
    enum Retry: Equatable {
        case all
        case swap(MealSlot)
    }

    let retry: Retry
    let message: String

    var title: String {
        switch retry {
        case .all: String(localized: "没有生成成功")
        case .swap: String(localized: "没有换成功")
        }
    }
}

/// 一道菜的摘要：菜名、热量和营养素、时间和食材数（「食谱」页和「推荐下一餐」的卡片共用）
struct RecipeSummaryLabel: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipe.name)
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
            Text(
                "\(recipe.caloriesKcal.noDecimal) 千卡 · 蛋白质 \(recipe.proteinG.oneDecimal) · 碳水 \(recipe.carbsG.oneDecimal) · 脂肪 \(recipe.fatG.oneDecimal) 克"
            )
            .font(.caption)
            .foregroundStyle(AppColors.textSecondary)
            Text("约 \(recipe.cookingMinutes) 分钟 · \(recipe.ingredients.count) 种食材")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
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
