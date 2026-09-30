//
//  NextMealSheet.swift
//  FoodTracker
//
//  「推荐下一餐」：按今天剩下的热量，为还没吃的下一顿正餐生成一份食谱。
//  和「食谱」页共用后端接口和每天的次数；打开时不会自动生成，要点按钮才会调用（每次都花钱、占次数）。
//  后端不用改：把每日目标按同一个倍数缩小后发过去，后端按比例拆出来的这一餐正好是要推荐的量（见 NextMealBudget）。
//

import SwiftData
import SwiftUI

struct NextMealSheet: View {
    let profile: UserProfile
    let budget: NextMealBudget

    // 偏好和忌口（和「食谱」页读同一份本地数据）
    @AppStorage(RecipePrefKeys.preferences) private var preferencesText = ""
    @AppStorage(RecipePrefKeys.allergies) private var allergiesText = ""
    @AppStorage(RecipePrefKeys.dislikes) private var dislikesText = ""
    @AppStorage(RecipePrefKeys.cookingMinutes) private var cookingMinutes = 30

    @Environment(\.dismiss) private var dismiss
    @State private var recipe: Recipe?  // 生成的这一餐
    @State private var isGenerating = false
    @State private var remaining: Int?  // 今天还能生成几次；问不到就不显示
    @State private var errorMessage: String?  // 有值时弹出出错提示

    private var mealName: String { budget.meal.title }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(introText)
                    let meal = budget.mealTargets
                    Text(
                        HintCopy.nextMealBudgetLine(
                            kcal: Int(meal.calories.rounded()), proteinG: Int(meal.proteinG.rounded()),
                            carbsG: Int(meal.carbsG.rounded()), fatG: Int(meal.fatG.rounded()))
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                Text(HintCopy.generatingNextMeal)
                            } else {
                                Label(HintCopy.generateNextMeal(mealName: mealName), systemImage: "sparkles")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isGenerating || remaining == 0)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    if let remaining {
                        Text(remaining == 0 ? HintCopy.quotaUsedUp : HintCopy.quotaRemaining(remaining))
                    }
                }

                if let recipe {
                    Section {
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            RecipeSummaryLabel(recipe: recipe)
                        }
                    } header: {
                        Label(recipe.meal.title, systemImage: recipe.meal.systemImage)
                    }
                }
            }
            .navigationTitle(HintCopy.nextMealTitle(mealName: mealName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(HintCopy.done) { dismiss() }
                }
            }
            .alert(HintCopy.generateFailedTitle, isPresented: isShowingError) {
                Button(HintCopy.ok, role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            // 固定在页面最底部的提示（和「食谱」页一样）
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
            // 打开时问一下今天还能生成几次（不花钱、不占次数）；问不到就不显示
            .task {
                if let quota = try? await APIClient.quota() {
                    remaining = quota.recipesRemaining
                }
            }
        }
    }

    /// 说明文字：剩下的不够一顿正餐时，如实说明按 320 千卡推荐（不让人「省着吃」）
    private var introText: String {
        budget.wasRaisedToFloor
            ? HintCopy.nextMealRaisedToFloor(
                remainingKcal: HintEngine.roundToTen(budget.remainingKcal),
                floorKcal: Int(NextMealBudget.minMealKcal), mealName: mealName)
            : HintCopy.nextMealIntro(mealKcal: HintEngine.roundToTen(budget.mealKcal), mealName: mealName)
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// 只生成这一餐：把缩小后的「每日目标」发给后端，后端按比例拆出来正好是这一餐的量
    private func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        let request = RecipeRequest.make(
            goal: profile.bodyInfo.goal, targets: budget.requestTargets, preferencesText: preferencesText,
            allergiesText: allergiesText, dislikesText: dislikesText, cookingMinutes: cookingMinutes,
            meals: [budget.meal], excludeNames: [])
        do {
            let result = try await APIClient.recipes(request)
            recipe = result.recipes.first
            remaining = result.remainingToday
        } catch {
            // 没网、超时、次数用完等说明都来自 APIClient
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let profile = UserProfile(
        body: BodyInfo(sex: .female, age: 28, heightCm: 165, weightKg: 60, activity: .light, goal: .loseFat))
    NextMealSheet(profile: profile, budget: NextMealBudget(meal: .dinner, remainingKcal: 150, targets: profile.targets))
        .modelContainer(for: AppModels.all, inMemory: true)
}
