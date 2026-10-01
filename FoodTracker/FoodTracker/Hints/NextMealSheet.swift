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
    @State private var errorMessage: String?  // 有值时显示出错卡片（可以重试）
    @State private var pendingAIAction: PendingAIAction?  // 还没同意使用 AI 时，先记下要做的生成，同意后再做
    @State private var detent: PresentationDetent = .medium  // 先开半屏；生成好以后拉到全屏

    private var mealName: String { budget.meal.title }

    var body: some View {
        NavigationStack {
            AppForm {
                // 这一餐按多少千卡推荐：一段说明 + 一行三大营养素（燕麦色的辅助卡片）
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(introText)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    let meal = budget.mealTargets
                    Text(
                        HintCopy.nextMealBudgetLine(
                            kcal: Int(meal.calories.rounded()), proteinG: Int(meal.proteinG.rounded()),
                            carbsG: Int(meal.carbsG.rounded()), fatG: Int(meal.fatG.rounded()))
                    )
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                }
                .padding(AppSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(.muted)

                VStack(spacing: AppSpacing.xs) {
                    Button {
                        // 没同意过使用 AI 时，先弹出说明；同意后才发送这一餐的目标和偏好
                        AIConsent.perform(pending: $pendingAIAction) { Task { await generate() } }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            if isGenerating {
                                AppLoadingIndicator(onBrand: true)
                                Text(HintCopy.generatingNextMeal)
                            } else {
                                Label(HintCopy.generateNextMeal(mealName: mealName), systemImage: "sparkles")
                            }
                        }
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(remaining == 0)
                    .allowsHitTesting(!isGenerating)
                    if let remaining {
                        Text(remaining == 0 ? HintCopy.quotaUsedUp : HintCopy.quotaRemaining(remaining))
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }

                // 没生成成功：和其他出错一样的样子，可以重试（不弹警告框）
                if let errorMessage {
                    BrandedStateView(kind: .error, title: HintCopy.generateFailedTitle, message: errorMessage, visualWidth: 56) {
                        Button("重试") { AIConsent.perform(pending: $pendingAIAction) { Task { await generate() } } }
                            .buttonStyle(.appPrimary)
                        Button("关闭") { self.errorMessage = nil }
                            .buttonStyle(.appTertiary)
                    }
                    .padding(.vertical, AppSpacing.md)
                    .appCard(.primary)
                }

                if let recipe {
                    AppFormSection(title: recipe.meal.title, accessory: { EmptyView() }) {
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            HStack(spacing: AppSpacing.xs) {
                                RecipeSummaryLabel(recipe: recipe)
                                Spacer(minLength: AppSpacing.xs)
                                AppChevron()
                            }
                            .padding(AppSpacing.cardPadding)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AppPressStyle(scales: false))
                    }
                }

                // 只在最下面说一次「估算值」，点 ⓘ 看完整说明
                AIFootnote()
                    .frame(maxWidth: .infinity)
            }
            .toolbar(.hidden, for: .navigationBar)
            .appSheetHeader(
                AppSheetHeader(
                    title: HintCopy.nextMealTitle(mealName: mealName), confirmTitle: HintCopy.done, onConfirm: { dismiss() }))
            // 第一次生成前：说明会发送什么、发给谁，同意后才发送（见 AIConsent.swift）
            .aiConsentSheet(pending: $pendingAIAction)
            // 打开时问一下今天还能生成几次（不花钱、不占次数）；问不到就不显示
            .task {
                if let quota = try? await APIClient.quota() {
                    remaining = quota.recipesRemaining
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .appSheet()
        .onChange(of: recipe == nil) { _, isEmpty in
            if !isEmpty { withAnimation { detent = .large } }
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

    /// 只生成这一餐：把缩小后的「每日目标」发给后端，后端按比例拆出来正好是这一餐的量
    private func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
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
